# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ActiveCache do
  describe '.instance' do
    it 'initializes tick query dependency' do
      cache = described_class.instance
      expect(cache.instance_variable_get(:@tick_query)).to eq(Live::TickQuery)
    end
  end
end
