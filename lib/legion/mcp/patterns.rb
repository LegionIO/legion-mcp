# frozen_string_literal: true

# Barrel file: requires all Tier 0 pattern routing system modules.
# These modules live in the Legion::MCP namespace (flat) but are
# grouped here for organizational clarity.

require_relative 'pattern_store'
require_relative 'pattern_schema'
require_relative 'pattern_compiler'
require_relative 'pattern_exchange'
require_relative 'pattern_gossip'
require_relative 'tier_router'
require_relative 'context_guard'
require_relative 'context_compiler'
require_relative 'observer'
require_relative 'state_tracker'
require_relative 'gap_detector'
require_relative 'cold_start'
require_relative 'self_generate'
