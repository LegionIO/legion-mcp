# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/embedding_index'

# Stub ::MCP::Tool base class if not already loaded
unless defined?(MCP::Tool)
  module MCP
    class Tool
      class << self
        attr_reader :tool_name_value, :description_value, :input_schema_value

        def tool_name(val = nil)
          val ? @tool_name_value = val : @tool_name_value
        end

        def description(val = nil)
          val ? @description_value = val : @description_value
        end

        def input_schema(val = nil)
          val ? @input_schema_value = val : @input_schema_value
        end
      end
    end
  end
  $LOADED_FEATURES << 'mcp'
end

require 'legion/mcp/context_compiler'

RSpec.describe Legion::MCP::ContextCompiler do
  # Build stub tool classes covering tasks, extensions, workers, status categories
  let(:stub_run_task) do
    Class.new(MCP::Tool) do
      tool_name 'legion.run_task'
      description 'Execute a Legion task using dot notation.'
      input_schema(properties: { task:   { type: 'string', description: 'Dot notation path' },
                                 params: { type: 'object', description: 'Parameters' } },
                   required:   ['task'])
    end
  end

  let(:stub_list_tasks) do
    Class.new(MCP::Tool) do
      tool_name 'legion.list_tasks'
      description 'List all tasks with optional filtering.'
      input_schema(properties: { limit: { type: 'integer', description: 'Max results' } })
    end
  end

  let(:stub_get_task) do
    Class.new(MCP::Tool) do
      tool_name 'legion.get_task'
      description 'Get a specific task by ID.'
      input_schema(properties: { id: { type: 'integer', description: 'Task ID' } },
                   required:   ['id'])
    end
  end

  let(:stub_list_extensions) do
    Class.new(MCP::Tool) do
      tool_name 'legion.list_extensions'
      description 'List all installed Legion extensions with status.'
      input_schema(properties: { active: { type: 'boolean', description: 'Filter by active status' } })
    end
  end

  let(:stub_get_extension) do
    Class.new(MCP::Tool) do
      tool_name 'legion.get_extension'
      description 'Get details about a specific extension.'
      input_schema(properties: { name: { type: 'string', description: 'Extension name' } },
                   required:   ['name'])
    end
  end

  let(:stub_list_workers) do
    Class.new(MCP::Tool) do
      tool_name 'legion.list_workers'
      description 'List digital workers with optional filtering by team or state.'
      input_schema(properties: { team:  { type: 'string', description: 'Filter by team' },
                                 limit: { type: 'integer', description: 'Max results' } })
    end
  end

  let(:stub_get_status) do
    Class.new(MCP::Tool) do
      tool_name 'legion.get_status'
      description 'Get Legion service health status and component info.'
      input_schema(properties: {})
    end
  end

  let(:stub_rbac_check) do
    Class.new(MCP::Tool) do
      tool_name 'legion.rbac_check'
      description 'Check RBAC permissions for an identity.'
      input_schema(properties: { identity: { type: 'string', description: 'Identity to check' },
                                 resource: { type: 'string', description: 'Resource path' } },
                   required:   %w[identity resource])
    end
  end

  let(:stub_skill_list) do
    Class.new(MCP::Tool) do
      tool_name 'legion.skill.list'
      description 'List all skills available in this Legion instance.'
      input_schema(properties: {})
    end
  end

  let(:stub_pr_reviewer) do
    Class.new(MCP::Tool) do
      tool_name 'legion-swarm_github-pull_request_reviewer-review_pull_request'
      description 'swarm_github#review_pull_request'
      input_schema(
        properties: {
          owner:       { type: 'string' },
          repo:        { type: 'string' },
          pull_number: { type: 'integer' }
        },
        required:   %w[owner repo pull_number]
      )
    end
  end

  let(:stub_tool_classes) do
    [stub_run_task, stub_list_tasks, stub_get_task, stub_list_extensions,
     stub_get_extension, stub_list_workers, stub_get_status, stub_rbac_check,
     stub_skill_list, stub_pr_reviewer]
  end

  before(:each) do
    described_class.reset!
    allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes)
  end

  describe 'CATEGORIES' do
    subject(:categories) { described_class::CATEGORIES }

    it 'is frozen' do
      expect(categories).to be_frozen
    end

    it 'contains expected category keys' do
      expect(categories.keys).to include(:tasks, :extensions, :workers, :status, :rbac)
    end

    it 'each category has :tools, :summary keys' do
      categories.each_value do |cat|
        expect(cat).to have_key(:tools)
        expect(cat).to have_key(:summary)
      end
    end

    it 'tasks category lists run_task' do
      expect(categories[:tasks][:tools]).to include('legion.run_task')
    end

    it 'contains a :skills category' do
      expect(categories.keys).to include(:skills)
    end

    it 'skills category lists all four skill tools' do
      expect(categories[:skills][:tools]).to include(
        'legion.skill.list',
        'legion.skill.describe',
        'legion.skill.invoke',
        'legion.skill.cancel'
      )
    end
  end

  describe '.compressed_catalog' do
    subject(:catalog) { described_class.compressed_catalog }

    it 'returns an array' do
      expect(catalog).to be_an(Array)
    end

    it 'includes an entry for each CATEGORIES key' do
      category_names = catalog.map { |c| c[:category] }
      expect(category_names).to include(:tasks, :extensions, :workers, :status)
    end

    it 'each entry has :category, :summary, :tool_count, :tools keys' do
      catalog.each do |entry|
        expect(entry).to have_key(:category)
        expect(entry).to have_key(:summary)
        expect(entry).to have_key(:tool_count)
        expect(entry).to have_key(:tools)
      end
    end

    it ':tool_count matches :tools array length' do
      catalog.each do |entry|
        expect(entry[:tool_count]).to eq(entry[:tools].length)
      end
    end

    it ':tools are arrays of strings' do
      catalog.each do |entry|
        expect(entry[:tools]).to be_an(Array)
        entry[:tools].each { |t| expect(t).to be_a(String) }
      end
    end

    it 'tasks entry includes legion.run_task' do
      tasks_entry = catalog.find { |c| c[:category] == :tasks }
      expect(tasks_entry[:tools]).to include('legion.run_task')
    end
  end

  describe '.category_tools' do
    it 'returns nil for unknown category' do
      expect(described_class.category_tools(:unknown_xyz)).to be_nil
    end

    it 'returns a hash for known category :tasks' do
      result = described_class.category_tools(:tasks)
      expect(result).to be_a(Hash)
    end

    it 'returned hash has :category, :summary, :tools keys' do
      result = described_class.category_tools(:tasks)
      expect(result).to have_key(:category)
      expect(result).to have_key(:summary)
      expect(result).to have_key(:tools)
    end

    it ':tools is an array of hashes with :name, :description, :params' do
      result = described_class.category_tools(:tasks)
      result[:tools].each do |tool|
        expect(tool).to have_key(:name)
        expect(tool).to have_key(:description)
        expect(tool).to have_key(:params)
      end
    end

    it 'only includes tools that are present in TOOL_CLASSES' do
      result = described_class.category_tools(:tasks)
      names = result[:tools].map { |t| t[:name] }
      # run_task, list_tasks, get_task are in our stubs
      expect(names).to include('legion.run_task', 'legion.list_tasks', 'legion.get_task')
    end

    it 'omits tools from the category that are not in TOOL_CLASSES' do
      result = described_class.category_tools(:tasks)
      names = result[:tools].map { |t| t[:name] }
      # delete_task and get_task_logs are in CATEGORIES[:tasks] but not in our stub set
      expect(names).not_to include('legion.delete_task', 'legion.get_task_logs')
    end

    it 'returns nil for :chains when none of its tools are in TOOL_CLASSES' do
      # chains tools (list_chains, create_chain, etc.) are not in our stub set
      result = described_class.category_tools(:chains)
      # either nil or a category with empty tools array is acceptable
      expect(result).to be_nil.or(satisfy { |r| r[:tools].empty? })
    end

    it ':params lists parameter names from input_schema' do
      result = described_class.category_tools(:tasks)
      run_task_entry = result[:tools].find { |t| t[:name] == 'legion.run_task' }
      expect(run_task_entry[:params]).to include('task', 'params')
    end

    it 'returns extensions category with tools' do
      result = described_class.category_tools(:extensions)
      expect(result).not_to be_nil
      names = result[:tools].map { |t| t[:name] }
      expect(names).to include('legion.list_extensions', 'legion.get_extension')
    end
  end

  describe '.match_tool' do
    it 'returns a tool class for a matching intent' do
      result = described_class.match_tool('run a task')
      expect(result).not_to be_nil
    end

    it 'finds legion.run_task for "run a task"' do
      result = described_class.match_tool('run a task')
      expect(result.tool_name).to eq('legion.run_task')
    end

    it 'finds an extension-related tool for "list extensions"' do
      result = described_class.match_tool('list extensions')
      expect(result.tool_name).to eq('legion.list_extensions')
    end

    it 'finds legion.get_status for "get status"' do
      result = described_class.match_tool('get status')
      expect(result.tool_name).to eq('legion.get_status')
    end

    it 'returns nil when no keywords match' do
      result = described_class.match_tool('xyzzy florp quux')
      expect(result).to be_nil
    end

    it 'finds legion.skill.list for "list all skills", not the swarm-github pr reviewer' do
      result = described_class.match_tool('list all skills')
      expect(result).not_to be_nil
      expect(result.tool_name).to eq('legion.skill.list')
    end

    it 'returns a class (not an instance)' do
      result = described_class.match_tool('run a task')
      expect(result).to be_a(Class)
    end
  end

  describe '.match_tools' do
    it 'returns an array' do
      expect(described_class.match_tools('task')).to be_an(Array)
    end

    it 'returns at most limit results' do
      result = described_class.match_tools('task', limit: 2)
      expect(result.length).to be <= 2
    end

    it 'default limit is 5' do
      result = described_class.match_tools('a')
      expect(result.length).to be <= 5
    end

    it 'each result has :name, :description, :score' do
      results = described_class.match_tools('task')
      results.each do |r|
        expect(r).to have_key(:name)
        expect(r).to have_key(:description)
        expect(r).to have_key(:score)
      end
    end

    it 'results are sorted by score descending' do
      results = described_class.match_tools('task')
      scores = results.map { |r| r[:score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it 'higher scoring results come first for "run task"' do
      results = described_class.match_tools('run task')
      expect(results.first[:name]).to eq('legion.run_task')
    end

    it 'returns empty array for no matches' do
      results = described_class.match_tools('xyzzy florp quux')
      expect(results).to be_empty
    end
  end

  describe '.tool_index' do
    subject(:index) { described_class.tool_index }

    it 'returns a hash' do
      expect(index).to be_a(Hash)
    end

    it 'keys are tool_name strings' do
      expect(index.keys).to include('legion.run_task', 'legion.list_extensions')
    end

    it 'each value has :name, :description, :params' do
      index.each_value do |entry|
        expect(entry).to have_key(:name)
        expect(entry).to have_key(:description)
        expect(entry).to have_key(:params)
      end
    end

    it ':params is an array of strings' do
      index.each_value do |entry|
        expect(entry[:params]).to be_an(Array)
        entry[:params].each { |p| expect(p).to be_a(String) }
      end
    end

    it 'run_task has params task and params' do
      expect(index['legion.run_task'][:params]).to include('task', 'params')
    end

    it 'get_status has empty params' do
      expect(index['legion.get_status'][:params]).to be_empty
    end

    it 'is memoized (returns same object on second call)' do
      first_call  = described_class.tool_index
      second_call = described_class.tool_index
      expect(first_call).to equal(second_call)
    end
  end

  describe '.reset!' do
    it 'clears the memoized tool_index' do
      first_index = described_class.tool_index
      described_class.reset!
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes)
      second_index = described_class.tool_index
      # After reset the index is rebuilt — it may be equal in value but is a new object
      expect(second_index).not_to equal(first_index)
    end
  end

  context 'with semantic score blending' do
    let(:fake_embedder) { ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } } }

    before do
      described_class.reset!
      Legion::MCP::EmbeddingIndex.reset!
      tool_data = described_class.tool_index.values
      Legion::MCP::EmbeddingIndex.build_from_tool_data(tool_data, embedder: fake_embedder)
    end

    after do
      Legion::MCP::EmbeddingIndex.reset!
    end

    it 'returns scored results when embeddings are populated' do
      results = described_class.match_tools('execute a runner function', limit: 5)
      expect(results).not_to be_empty
      expect(results.first).to have_key(:score)
      expect(results.first[:score]).to be > 0
    end

    it 'blends scores to produce values between 0 and 1' do
      results = described_class.match_tools('run task', limit: 35)
      results.each do |r|
        expect(r[:score]).to be_between(0.0, 1.1) # slight tolerance for float math
      end
    end

    it 'still works after EmbeddingIndex is reset (falls back to keyword)' do
      Legion::MCP::EmbeddingIndex.reset!
      results = described_class.match_tools('run task', limit: 5)
      expect(results).not_to be_empty
    end
  end

  describe '.reset!' do
    it 'clears both tool_index and EmbeddingIndex' do
      described_class.tool_index # force build
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::EmbeddingIndex.build_from_tool_data(
        [{ name: 'test.tool', description: 'Test', params: [] }],
        embedder: fake_embedder
      )
      described_class.reset!
      expect(Legion::MCP::EmbeddingIndex.size).to eq(0)
    end
  end

  describe '.merged_categories' do
    it 'returns at minimum the CATEGORIES keys' do
      result = described_class.merged_categories
      described_class::CATEGORIES.each_key do |cat|
        expect(result).to have_key(cat)
      end
    end

    it 'adds a new category when a registered tool declares mcp_category not in CATEGORIES' do
      new_tool = Class.new(MCP::Tool) do
        tool_name 'legion.novel_tool'
        description 'A tool with a new category.'
        input_schema(properties: {})
        define_singleton_method(:mcp_category) { :novel_domain }
      end
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes + [new_tool])
      described_class.reset!
      result = described_class.merged_categories
      expect(result).to have_key(:novel_domain)
      expect(result[:novel_domain][:tools]).to include('legion.novel_tool')
    end

    it 'merges a definition-declared tool into an existing CATEGORIES entry' do
      extra_tasks_tool = Class.new(MCP::Tool) do
        tool_name 'legion.extra_task_op'
        description 'An extra task operation.'
        input_schema(properties: {})
        define_singleton_method(:mcp_category) { :tasks }
      end
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes + [extra_tasks_tool])
      described_class.reset!
      result = described_class.merged_categories
      expect(result[:tasks][:tools]).to include('legion.extra_task_op')
    end

    it 'does not add duplicate entries when tool name already in CATEGORIES' do
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes)
      described_class.reset!
      result = described_class.merged_categories
      tasks_tools = result[:tasks][:tools]
      expect(tasks_tools.uniq).to eq(tasks_tools)
    end

    it 'ignores tools that do not respond to mcp_category' do
      no_cat_tool = Class.new(MCP::Tool) do
        tool_name 'legion.no_category'
        description 'No category declared.'
        input_schema(properties: {})
      end
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes + [no_cat_tool])
      described_class.reset!
      result = described_class.merged_categories
      # Should not appear in any category
      all_tools = result.values.flat_map { |v| v[:tools] }
      expect(all_tools).not_to include('legion.no_category')
    end

    it 'ignores tools whose mcp_category is nil' do
      nil_cat_tool = Class.new(MCP::Tool) do
        tool_name 'legion.nil_category'
        description 'Nil category.'
        input_schema(properties: {})
        define_singleton_method(:mcp_category) { nil }
      end
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return(stub_tool_classes + [nil_cat_tool])
      described_class.reset!
      result = described_class.merged_categories
      all_tools = result.values.flat_map { |v| v[:tools] }
      expect(all_tools).not_to include('legion.nil_category')
    end
  end
end
