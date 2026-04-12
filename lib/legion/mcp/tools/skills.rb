# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class SkillList < ::MCP::Tool
        tool_name 'legion.skill.list'
        description 'List all skills available in this Legion instance.'

        input_schema(properties: {})

        class << self
          include Legion::Logging::Helper

          def call
            return error_response('Skills not available: legion-llm not loaded') unless defined?(Legion::LLM::Skills::Registry)

            skills = Legion::LLM::Skills::Registry.all.map do |s|
              {
                name:          s.skill_name,
                namespace:     s.namespace,
                description:   s.description,
                trigger_words: s.trigger_words,
                trigger:       s.trigger
              }
            end
            text_response({ skills: skills, count: skills.size })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.skill_list.call')
            error_response("Failed to list skills: #{e.message}")
          end

          private

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end

      class SkillDescribe < ::MCP::Tool
        tool_name 'legion.skill.describe'
        description 'Describe a specific skill by its namespace:name key or bare name.'

        input_schema(
          properties: {
            name: {
              type:        'string',
              description: 'Skill key in namespace:name format (e.g. "superpowers:brainstorming") or bare skill name'
            }
          },
          required:   ['name']
        )

        class << self
          include Legion::Logging::Helper

          def call(name:)
            return error_response('Skills not available: legion-llm not loaded') unless defined?(Legion::LLM::Skills::Registry)

            skill = find_skill(name)
            return error_response("Skill '#{name}' not found") if skill.nil?

            text_response({
                            name:          skill.skill_name,
                            namespace:     skill.namespace,
                            description:   skill.description,
                            trigger_words: skill.trigger_words,
                            trigger:       skill.trigger,
                            follows_skill: skill.follows_skill,
                            steps:         skill.steps
                          })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.skill_describe.call')
            error_response("Failed to describe skill: #{e.message}")
          end

          private

          def find_skill(name)
            skill = Legion::LLM::Skills::Registry.find(name)
            return skill unless skill.nil?
            return nil if name.include?(':')

            Legion::LLM::Skills::Registry.all.find { |s| s.skill_name == name }
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end

      class SkillInvoke < ::MCP::Tool
        tool_name 'legion.skill.invoke'
        description 'Invoke a skill for a conversation. The skill will run its configured steps.'

        input_schema(
          properties: {
            name:            {
              type:        'string',
              description: 'Skill key in namespace:name format (e.g. "superpowers:brainstorming")'
            },
            conversation_id: {
              type:        'string',
              description: 'Conversation ID to associate the skill run with (optional — generated if omitted)'
            },
            initial_message: {
              type:        'string',
              description: 'Optional initial message to seed the skill run (defaults to "start skill")'
            }
          },
          required:   ['name']
        )

        class << self
          include Legion::Logging::Helper

          def call(name:, conversation_id: nil, initial_message: nil)
            return error_response('Skills not available: legion-llm not loaded') unless defined?(Legion::LLM::Skills::Registry)

            skill = Legion::LLM::Skills::Registry.find(name)
            return error_response("Skill '#{name}' not found") if skill.nil?

            conv_id = conversation_id || "conv_#{::SecureRandom.hex(8)}"
            invoke_skill(name, conv_id, initial_message)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.skill_invoke.call')
            error_response("Failed to invoke skill: #{e.message}")
          end

          private

          def invoke_skill(name, conv_id, initial_message)
            unless defined?(Legion::LLM::ConversationStore) && defined?(Legion::LLM::Pipeline::Executor)
              return text_response({ invoked: true, skill: name, conversation_id: conv_id,
                                     note: 'pipeline not available — skill state queued' })
            end

            Legion::LLM::ConversationStore.set_skill_state(conv_id, skill_key: name, resume_at: 0)
            req = Legion::LLM::Pipeline::Request.build(
              messages:        [{ role: :user, content: initial_message || 'start skill' }],
              conversation_id: conv_id,
              metadata:        { skill_invoke: true },
              stream:          false
            )
            result = Legion::LLM::Pipeline::Executor.new(req).call
            text_response({ invoked: true, skill: name, conversation_id: conv_id,
                            content: result.message[:content] })
          rescue StandardError => e
            Legion::LLM::ConversationStore.clear_skill_state(conv_id) if defined?(Legion::LLM::ConversationStore)
            raise e
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end

      class SkillCancel < ::MCP::Tool
        tool_name 'legion.skill.cancel'
        description 'Cancel an active skill run for a conversation.'

        input_schema(
          properties: {
            conversation_id: {
              type:        'string',
              description: 'Conversation ID whose active skill should be cancelled'
            }
          },
          required:   ['conversation_id']
        )

        class << self
          include Legion::Logging::Helper

          def call(conversation_id:)
            return error_response('ConversationStore not available') unless defined?(Legion::LLM::ConversationStore)

            result = Legion::LLM::ConversationStore.cancel_skill!(conversation_id)
            if result
              text_response({ cancelled: true, skill_key: result[:skill_key] })
            else
              text_response({ cancelled: false, reason: 'not_running' })
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.skill_cancel.call')
            error_response("Failed to cancel skill: #{e.message}")
          end

          private

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
