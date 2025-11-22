# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeSelector do
  let(:selector) { described_class.new }
  let(:mock_analyzer) { instance_double(Options::DerivativeChainAnalyzer) }

  before do
    allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(mock_analyzer)
    allow(Live::TickCache).to receive(:ltp).and_return(nil)
  end

  describe '#select' do
    context 'with valid candidates' do
      let(:candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 25_000.0,
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49081',
          lot_size: 75,
          ltp: 150.5,
          iv: 20.5,
          oi: 500_000,
          bid: 150.0,
          ask: 151.0,
          volume: 50_000,
          score: 0.85,
          symbol: 'NIFTY-25Jan2024-25000-CE',
          derivative_id: 123,
          reason: 'High score'
        }
      end

      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([candidate])
        allow(Live::TickCache).to receive(:ltp).and_return(150.5)
      end

      it 'returns normalized instrument hash' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)

        expect(result).to be_a(Hash)
        expect(result[:index]).to eq('NIFTY')
        expect(result[:strike]).to eq(25_000)
        expect(result[:option_type]).to eq('CE')
      end

      it 'includes required fields in normalized hash' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)

        expect(result[:ltp]).to eq(150.5)
        expect(result[:lot_size]).to eq(75)
        expect(result[:security_id]).to eq('49081')
      end
    end

    context 'when no candidates from analyzer' do
      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([])
      end

      it 'returns nil' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)
        expect(result).to be_nil
      end
    end

    context 'when candidate fails index rules' do
      let(:invalid_candidate) do
        {
          strike: 25_000.0,
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49081',
          lot_size: 75,
          ltp: 10.0, # Below minimum premium
          volume: 5_000, # Below minimum volume
          bid: 9.0,
          ask: 11.0
        }
      end

      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([invalid_candidate])
      end

      it 'returns nil' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)
        expect(result).to be_nil
      end
    end

    context 'with unknown index' do
      it 'raises SelectionError' do
        expect do
          selector.select(index_key: 'UNKNOWN', direction: :bullish)
        end.to raise_error(Options::StrikeSelector::SelectionError, /Unknown index/)
      end
    end
  end
end
