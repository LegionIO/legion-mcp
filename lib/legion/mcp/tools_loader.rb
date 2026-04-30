# frozen_string_literal: true

# Requires all built-in MCP tool files so they are defined as Ruby constants.
# Only MCP-specific tools and legion-data CRUD tools remain here.
# Extension-owned tools are discovered dynamically via Legion::Settings::Extensions.

# MCP-specific tools
require_relative 'tools/do_action'
require_relative 'tools/discover_tools'
require_relative 'tools/plan_action'
require_relative 'tools/search_sessions'
require_relative 'tools/skills'
require_relative 'tools/tool_audit'
require_relative 'tools/state_diff'
require_relative 'tools/structural_index'

# legion-data CRUD tools
require_relative 'tools/run_task'
require_relative 'tools/describe_runner'
require_relative 'tools/list_tasks'
require_relative 'tools/get_task'
require_relative 'tools/delete_task'
require_relative 'tools/get_task_logs'
require_relative 'tools/list_chains'
require_relative 'tools/create_chain'
require_relative 'tools/update_chain'
require_relative 'tools/delete_chain'
require_relative 'tools/list_relationships'
require_relative 'tools/create_relationship'
require_relative 'tools/update_relationship'
require_relative 'tools/delete_relationship'
require_relative 'tools/list_schedules'
require_relative 'tools/create_schedule'
require_relative 'tools/update_schedule'
require_relative 'tools/delete_schedule'
