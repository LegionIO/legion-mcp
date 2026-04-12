# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class SkillList < ::MCP::Tool
        tool_name 'legion.skill.list'
        description 'List all skills available in this Legion instance.'

        input_schema(properties: {})

        class << self
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
        description 'Describe a specific skill by its namespace:name key.'

        input_schema(
          properties: {
            name: {
              type:        'string',
              description: 'Skill key in namespace:name format (e.g. "superpowers:brainstorming")'
            }
          },
          required:   ['name']
        )

        class << self
          def call(name:)
            return error_response('Skills not available: legion-llm not loaded') unless defined?(Legion::LLM::Skills::Registry)

            skill = Legion::LLM::Skills::Registry.find(name)
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
            error_response("Failed to describe skill: #{e.message}")
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
              description: 'Conversation ID to associate the skill run with'
            }
          },
          required:   %w[name conversation_id]
        )

        class << self
          def call(name:, conversation_id:)
            return error_response('Skills not available: legion-llm not loaded') unless defined?(Legion::LLM::Skills::Registry)

            skill = Legion::LLM::Skills::Registry.find(name)
            return error_response("Skill '#{name}' not found") if skill.nil?

            text_response({
                            invoked:         true,
                            skill:           name,
                            conversation_id: conversation_id,
                            steps:           skill.steps
                          })
          rescue StandardError => e
            error_response("Failed to invoke skill: #{e.message}")
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
          def call(conversation_id:)
            return error_response('ConversationStore not available') unless defined?(Legion::LLM::ConversationStore)

            result = Legion::LLM::ConversationStore.cancel_skill!(conversation_id)
            if result
              text_response({ cancelled: true, skill_key: result[:skill_key] })
            else
              text_response({ cancelled: false, reason: 'not_running' })
            end
          rescue StandardError => e
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
