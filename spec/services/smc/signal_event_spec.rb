# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::SignalEvent do
  describe '#valid?' do
    it 'returns true for call/put' do
      instrument = instance_double('Instrument')

      call_signal = described_class.new(
        instrument: instrument,
        decision: :call,
        timeframe: '5m',
        price: 100,
        reasons: ['HTF discount']
      )

      put_signal = described_class.new(
        instrument: instrument,
        decision: :put,
        timeframe: '5m',
        price: 100,
        reasons: ['HTF premium']
      )

      expect(call_signal).to be_valid
      expect(put_signal).to be_valid
    end

    it 'returns false for non trade decisions' do
      instrument = instance_double('Instrument')

      signal = described_class.new(
        instrument: instrument,
        decision: :no_trade,
        timeframe: '5m',
        price: 100,
        reasons: []
      )

      expect(signal).not_to be_valid
    end
  end
end

