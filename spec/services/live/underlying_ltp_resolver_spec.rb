# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnderlyingLtpResolver do
  let(:test_class) { Class.new { include Live::UnderlyingLtpResolver } }
  let(:resolver) { test_class.new }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [
        { key: 'NIFTY', segment: 'IDX_I', sid: '13' },
        { key: 'SENSEX', segment: 'IDX_I', sid: '51' }
      ]
    })
  end

  describe '#resolve_underlying_ltp' do
    it 'returns LTP for a known index key' do
      tick = double(ltp: 23_850.5)
      allow(Live::TickQuery).to receive(:for_security)
        .with(segment: 'IDX_I', security_id: '13')
        .and_return(tick)

      expect(resolver.resolve_underlying_ltp('NIFTY')).to eq(23_850.5)
    end

    it 'returns nil for unknown index key' do
      expect(resolver.resolve_underlying_ltp('UNKNOWN')).to be_nil
    end

    it 'returns nil when index_key is nil' do
      expect(resolver.resolve_underlying_ltp(nil)).to be_nil
    end

    it 'returns nil when TickQuery raises' do
      allow(Live::TickQuery).to receive(:for_security).and_raise(StandardError)
      expect(resolver.resolve_underlying_ltp('NIFTY')).to be_nil
    end

    it 'returns nil when TickQuery returns nil' do
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      expect(resolver.resolve_underlying_ltp('NIFTY')).to be_nil
    end
  end
end
