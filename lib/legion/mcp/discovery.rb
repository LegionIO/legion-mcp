# frozen_string_literal: true

# Barrel file: requires all tool discovery and adaptation modules.
# These modules live in the Legion::MCP namespace (flat) but are
# grouped here for organizational clarity.

require_relative 'function_discovery'
require_relative 'tool_adapter'
require_relative 'tool_governance'
require_relative 'tool_quality'
require_relative 'tools_loader'
require_relative 'deferred_registry'
require_relative 'dynamic_injector'
require_relative 'catalog_dispatcher'
require_relative 'usage_filter'
require_relative 'embedding_index'
require_relative 'structural_index'
require_relative 'override_broadcast'
