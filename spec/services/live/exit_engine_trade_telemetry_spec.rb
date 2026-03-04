# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ExitEngine do
  let(:router) { instance_double(TradingSystem::OrderRouter) }
  let(:engine) { described_class.new(order_router: router) }

  describe '#resolved_entry_tf' do
    it 'defaults to 1m when metadata has no entry_tf' do
      tracker = instance_double(PositionTracker, meta: {})
      expect(engine.send(:resolved_entry_tf, tracker)).to eq('1m')
    end
  end
end
