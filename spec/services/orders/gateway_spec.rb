# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Gateway do
  subject(:gateway) { described_class.new }

  describe '#exit_market' do
    it 'raises NotImplementedError' do
      expect { gateway.exit_market(:tracker) }
        .to raise_error(NotImplementedError, /must implement exit_market/)
    end
  end

  describe '#place_market' do
    it 'raises NotImplementedError' do
      expect { gateway.place_market(side: 'buy', segment: 'NSE', security_id: '1', qty: 10) }
        .to raise_error(NotImplementedError, /must implement place_market/)
    end
  end

  describe '#wallet_snapshot' do
    it 'raises NotImplementedError' do
      expect { gateway.wallet_snapshot }
        .to raise_error(NotImplementedError, /must implement wallet_snapshot/)
    end
  end

  describe '#cancel_order' do
    it 'raises NotImplementedError' do
      expect { gateway.cancel_order('order123') }
        .to raise_error(NotImplementedError, /must implement cancel_order/)
    end
  end

  describe '#on_tick' do
    it 'returns nil by default' do
      expect(gateway.on_tick(segment: 'NSE', security_id: '1', ltp: 100.0)).to be_nil
    end
  end
end
