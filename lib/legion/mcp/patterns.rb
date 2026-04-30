# frozen_string_literal: true

# Barrel file: requires all Tier 0 pattern routing system modules.
# Pattern modules live in Legion::MCP::Patterns namespace.

require_relative 'patterns/store'
require_relative 'patterns/schema'
require_relative 'patterns/compiler'
require_relative 'patterns/exchange'
require_relative 'patterns/gossip'
require_relative 'tier_router'
require_relative 'context_guard'
require_relative 'context_compiler'
require_relative 'observer'
require_relative 'state_tracker'
require_relative 'gap_detector'
require_relative 'cold_start'
require_relative 'self_generate'

# Backward compatibility — old flat names delegate to new namespace
Legion::MCP::PatternStore = Legion::MCP::Patterns::Store unless Legion::MCP.const_defined?(:PatternStore, false)
Legion::MCP::PatternSchema = Legion::MCP::Patterns::Schema unless Legion::MCP.const_defined?(:PatternSchema, false)
Legion::MCP::PatternCompiler = Legion::MCP::Patterns::Compiler unless Legion::MCP.const_defined?(:PatternCompiler, false)
Legion::MCP::PatternExchange = Legion::MCP::Patterns::Exchange unless Legion::MCP.const_defined?(:PatternExchange, false)
Legion::MCP::PatternGossip = Legion::MCP::Patterns::Gossip unless Legion::MCP.const_defined?(:PatternGossip, false)
