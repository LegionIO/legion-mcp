# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module MCP
    module LoggingSupport
      extend Legion::Logging::Helper
      module_function

      def info(event, **fields)
        emit(:info, event, **fields)
      end

      def warn(event, **fields)
        emit(:warn, event, **fields)
      end

      def debug(event, **fields)
        emit(:debug, event, **fields)
      end

      def request_id_from(*sources)
        sources.compact.each do |source|
          next unless source.respond_to?(:[])

          %i[request_id correlation_id trace_id].each do |key|
            value = source[key]
            return value.to_s unless blank?(value)
          end

          %w[request_id correlation_id trace_id].each do |key|
            value = source[key]
            return value.to_s unless blank?(value)
          end
        end

        nil
      end

      def summarize_text(value, max: 120)
        text = value.to_s.gsub(/\s+/, ' ').strip
        return '' if text.empty?
        return text if text.length <= max

        "#{text[0, max - 3]}..."
      end

      def summarize_params(params, max_pairs: 6)
        summarize_hash(params, max_pairs: max_pairs)
      end

      def summarize_hash(hash, max_pairs: 6)
        return '{}' unless hash.is_a?(Hash) && !hash.empty?

        pairs = hash.to_a.first(max_pairs).map do |key, value|
          "#{key}=#{summarize_value(value)}"
        end
        suffix = hash.size > max_pairs ? " +#{hash.size - max_pairs} more" : ''
        "{#{pairs.join(', ')}}#{suffix}"
      end

      def summarize_array(array, max_items: 6)
        return '[]' unless array.is_a?(Array) && !array.empty?

        items = array.first(max_items).map { |value| summarize_value(value) }
        suffix = array.size > max_items ? " +#{array.size - max_items} more" : ''
        "[#{items.join(', ')}]#{suffix}"
      end

      def summarize_result(result)
        if result.respond_to?(:error?) && result.respond_to?(:content)
          return "mcp_response(error=#{result.error?}, content_items=#{Array(result.content).size})"
        end

        case result
        when Hash
          "hash(keys=#{result.keys.first(8).join(',')})"
        when Array
          "array(size=#{result.size})"
        when NilClass
          'nil'
        else
          summarize_value(result)
        end
      end

      def summarize_identity(identity)
        case identity
        when Hash
          summarize_hash(identity, max_pairs: 4)
        when NilClass
          'none'
        else
          summarize_value(identity)
        end
      end

      def emit(level, event, **fields)
        message = "[mcp] #{event}"
        formatted = format_fields(fields)
        message = "#{message} #{formatted}" unless formatted.empty?
        logger = log
        return unless logger.respond_to?(level)

        logger.public_send(level, message)
      rescue StandardError
        nil
      end

      def format_fields(fields)
        fields.compact.filter_map do |key, value|
          next if blank?(value)

          "#{key}=#{format_value(value)}"
        end.join(' ')
      end

      def format_value(value)
        case value
        when String
          summarize_text(value).inspect
        when Symbol, Numeric, TrueClass, FalseClass
          value.inspect
        when Hash
          summarize_hash(value).inspect
        when Array
          summarize_array(value).inspect
        when NilClass
          'nil'
        else
          summarize_text(value.inspect).inspect
        end
      end

      def summarize_value(value)
        case value
        when String
          summarize_text(value)
        when Symbol, Numeric, TrueClass, FalseClass
          value.to_s
        when Hash
          summarize_hash(value)
        when Array
          summarize_array(value)
        when NilClass
          'nil'
        else
          summarize_text(value.inspect)
        end
      end

      def blank?(value)
        value.nil? || value == '' || value == []
      end
    end
  end
end
