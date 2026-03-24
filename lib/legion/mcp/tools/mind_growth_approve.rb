# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class MindGrowthApprove < ::MCP::Tool
        tool_name 'legion.mind_growth_approve'
        description 'Evaluate and score a mind growth proposal for approval.'

        input_schema(
          properties: {
            proposal_id: { type: 'string', description: 'ID of the proposal to evaluate' }
          },
          required:   ['proposal_id']
        )

        class << self
          def call(proposal_id:)
            return error_response('lex-mind-growth is not available') unless mind_growth_available?

            result = mind_growth_client.evaluate_proposal(proposal_id: proposal_id)
            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("MindGrowthApprove#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Failed to evaluate proposal: #{e.message}")
          end

          private

          def mind_growth_available?
            defined?(Legion::Extensions::MindGrowth::Client)
          end

          def mind_growth_client
            @mind_growth_client ||= Legion::Extensions::MindGrowth::Client.new
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
