# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::PermissionResolver do
  describe '.resolve' do
    let(:series) { double('CandleSeries', candles: [double('Candle')]) }
    let(:instrument) { instance_double(Instrument, candle_series: series) }

    before do
      allow(instrument).to receive(:candle_series).and_return(series)
      allow(Smc::Context).to receive(:new).and_return(double('Context'))
      allow(Smc::PermissionSnapshot).to receive(:from_contexts).and_return({})
      allow(Smc::SmcPermissionResolver).to receive(:resolve).and_return(:execution_only)
    end

    it 'passes the raw LTF candle series to AvrzStateResolver instead of an undefined variable' do
      allow(Smc::AvrzStateResolver).to receive(:resolve).and_call_original

      expect { described_class.resolve(symbol: 'NIFTY', instrument: instrument) }.not_to raise_error
      expect(Smc::AvrzStateResolver).to have_received(:resolve).with(symbol: 'NIFTY', ltf_series: series)
    end

    it 'does not silently fall back to the lenient rescue branch' do
      result = described_class.resolve(symbol: 'NIFTY', instrument: instrument)

      expect(result).to eq(:execution_only)
      expect(Smc::SmcPermissionResolver).to have_received(:resolve)
    end

    it 'blocks when the instrument is missing' do
      expect(described_class.resolve(symbol: 'NIFTY', instrument: nil)).to eq(:blocked)
    end

    it 'blocks when a required candle series is empty' do
      empty_series = double('CandleSeries', candles: [])
      allow(instrument).to receive(:candle_series).and_return(empty_series)

      expect(described_class.resolve(symbol: 'NIFTY', instrument: instrument)).to eq(:blocked)
    end
  end
end
