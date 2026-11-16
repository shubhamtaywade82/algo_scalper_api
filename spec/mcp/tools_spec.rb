# frozen_string_literal: true

require 'rails_helper'

# Every registered MCP tool must answer with parseable JSON on an empty database
# with the market-brief sources stubbed (the same sources the tools slice).
RSpec.describe 'MCP tool smoke' do # rubocop:disable RSpec/DescribeClass
  let(:sample_args) do
    { 'index' => 'NIFTY', 'position_id' => create(:position_tracker).id, 'section' => 'risk' }
  end

  before do
    Rails.application.eager_load!
    stub_market_brief_sources
  end

  ActionMCP::ToolsRegistry.tools.each_key do |name|
    it "#{name} returns JSON" do
      klass = ActionMCP::ToolsRegistry.find(name)
      required = Array(klass.to_h[:inputSchema]&.dig(:required)).map(&:to_s)
      response = klass.new(sample_args.slice(*required)).call

      expect(response.error?).to be(false), -> { response.to_h.inspect }
      expect(JSON.parse(response.contents.first.text)).to be_a(Hash)
    end
  end
end
