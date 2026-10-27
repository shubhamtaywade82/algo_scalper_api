# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GetAccountStatusTool do
  it 'takes no arguments' do
    expect(described_class.new.parameters_schema['properties']).to eq({})
  end
end
