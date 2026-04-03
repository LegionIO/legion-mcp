# frozen_string_literal: true

require 'json'

module Legion
  module MCP
    module StructuralIndex
      CACHE_PATH = File.expand_path('~/.legionio/cache/structural_index.json')

      extend Legion::Logging::Helper

      module_function

      def build
        {
          extensions:   scan_extensions,
          tools:        scan_tools,
          generated_at: Time.now.iso8601
        }
      end

      def scan_extensions
        return [] unless defined?(Legion::Extensions)

        extensions = if Legion::Extensions.respond_to?(:extensions)
                       Legion::Extensions.extensions || []
                     else
                       Legion::Extensions.instance_variable_get(:@extensions) || []
                     end

        extensions.filter_map do |ext|
          build_extension_entry(ext)
        rescue StandardError => e
          handle_exception(e, level: :debug, operation: 'legion.mcp.structural_index.scan_extensions')
          log.debug("StructuralIndex: skipping #{ext}: #{e.message}")
          nil
        end
      end

      def build_extension_entry(ext)
        runners = if ext.respond_to?(:runner_modules)
                    ext.runner_modules.filter_map { |rm| build_runner_entry(rm) }
                  else
                    []
                  end

        actors = if ext.respond_to?(:actor_modules)
                   ext.actor_modules.filter_map { |am| build_actor_entry(am) }
                 else
                   []
                 end

        name = ext.respond_to?(:extension_name) ? ext.extension_name : ext.class.name

        {
          name:    name,
          runners: runners,
          actors:  actors
        }
      end

      def build_runner_entry(runner_mod)
        settings = runner_mod.respond_to?(:settings) ? runner_mod.settings : {}
        functions = settings.is_a?(Hash) ? (settings[:functions] || {}) : {}

        {
          name:      runner_mod.respond_to?(:name) ? runner_mod.name : runner_mod.to_s,
          functions: functions.keys.map(&:to_s)
        }
      end

      def build_actor_entry(actor_mod)
        {
          name: actor_mod.respond_to?(:name) ? actor_mod.name : actor_mod.to_s,
          type: actor_mod.respond_to?(:actor_type) ? actor_mod.actor_type : 'unknown'
        }
      end

      def scan_tools
        Server.tool_registry.map do |tc|
          {
            name:        tc.tool_name,
            description: tc.description,
            catalog:     tc.respond_to?(:catalog_entry) && tc.catalog_entry ? true : false
          }
        end
      end

      def cached
        return nil unless File.exist?(CACHE_PATH)

        data = File.read(CACHE_PATH)
        Legion::JSON.load(data)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.structural_index.cached')
        nil
      end

      def save_cache(index = nil)
        index ||= build
        dir = File.dirname(CACHE_PATH)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(CACHE_PATH, Legion::JSON.dump(index))
        index
      end

      def invalidate_cache
        FileUtils.rm_f(CACHE_PATH)
      end

      def load_or_build
        cached || save_cache(build)
      end

      def filter(index, extension: nil, type: nil)
        result = index.dup
        result[:extensions] = result[:extensions]&.select { |e| e[:name]&.include?(extension) } || [] if extension
        apply_type_filter(result, type) if type
        result
      end

      def apply_type_filter(result, type)
        case type
        when 'tools'
          result.delete(:extensions)
        when 'extensions'
          result.delete(:tools)
        when 'runners'
          result[:extensions]&.each { |e| e.delete(:actors) }
          result.delete(:tools)
        when 'actors'
          result[:extensions]&.each { |e| e.delete(:runners) }
          result.delete(:tools)
        end
      end
    end
  end
end
