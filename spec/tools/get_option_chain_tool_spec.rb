# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GetOptionChainTool do
  it 'declares its JSON schema with RubyLLM 2.x `parameter`' do
    schema = described_class.new.parameters_schema
    expect(schema['properties'].keys).to eq(%w[index_key direction limit])
    expect(schema['properties']['limit']['type']).to eq('integer')
    expect(schema['required']).to eq(['index_key'])
  end
end
