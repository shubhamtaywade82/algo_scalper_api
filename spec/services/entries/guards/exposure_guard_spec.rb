# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/VerifiedDoubles
RSpec.describe Entries::Guards::ExposureGuard do
  let(:instrument) { instance_double(Instrument, id: 101) }
  let(:count_relation) { double('count_relation', count: 0) }
  let(:sum_relation) { double('sum_relation') }
  let(:active_relation) { double('ActiveRelation') }
  let(:context) do
    {
      index_cfg: { key: 'NIFTY', max_same_side: 2 },
      instrument: instrument,
      direction: :bullish,
      entry_metadata: nil,
      quantity: 65,
      ltp: 150.0,
      lot_size: 65
    }
  end

  before do
    allow(sum_relation).to receive(:sum).with('quantity * entry_price').and_return(0.0)
    allow(PositionTracker).to receive(:active).and_return(active_relation)
    allow(active_relation).to receive(:where).with(index_key: 'NIFTY').and_return(sum_relation)
    allow(active_relation).to receive(:where).with(side: 'long_ce').and_return(count_relation)
    allow(active_relation).to receive(:where).with(side: 'long_pe').and_return(count_relation)
    allow(count_relation).to receive(:where).with(any_args).and_return(count_relation)
    allow(count_relation).to receive(:limit).with(any_args).and_return(count_relation)
    allow(count_relation).to receive(:to_a).and_return([])
    allow(AlgoConfig).to receive(:fetch).and_return({ risk: { max_exposure_rupees: { 'NIFTY' => 1_000_000 } } })
    allow(Rails.logger).to receive(:warn)
  end

  describe '.call' do
    context 'when no active positions exist' do
      it 'sets side based on direction' do
        described_class.call(context)
        expect(context[:side]).to eq('long_ce')
      end

      it 'sets is_supertrend to false' do
        described_class.call(context)
        expect(context[:is_supertrend]).to be false
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when bearish direction' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY', max_same_side: 2 },
          instrument: instrument,
          direction: :bearish,
          entry_metadata: nil,
          quantity: 65,
          ltp: 150.0,
          lot_size: 65
        }
      end

      it 'sets side to long_pe' do
        described_class.call(context)
        expect(context[:side]).to eq('long_pe')
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when supertrend contract' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          instrument: instrument,
          direction: :bullish,
          entry_metadata: { entry_contract: 'supertrend_machine_v1' }
        }
      end

      before do
        allow(active_relation).to receive(:by_index_key).with('NIFTY').and_return(double('scope', exists?: false))
      end

      context 'when no active supertrend position exists' do
        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'when active supertrend position already exists' do
        before do
          allow(active_relation).to receive(:by_index_key).with('NIFTY').and_return(double('scope', exists?: true))
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to include(blocked: /Supertrend.*active position already exists/)
        end
      end
    end

    context 'when max_same_side limit reached' do
      let(:limit_reached_relation) { double('limit_reached', count: 2) }

      before do
        allow(count_relation).to receive(:limit).with(3).and_return(limit_reached_relation)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /exposure limit/)
      end
    end
  end

  describe '.exposure_ok?' do
    context 'when rupee exposure limit is exceeded' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ risk: { max_exposure_rupees: { 'NIFTY' => 10_000 } } })
        allow(sum_relation).to receive(:sum).with('quantity * entry_price').and_return(8_000.0)
      end

      it 'returns false' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: context
        )
        expect(result).to be false
      end

      it 'caches the result in context' do
        described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: context
        )
        expect(context["exposure_check_101_long_ce"]).to be false
      end
    end

    context 'when max_same_side is not configured' do
      it 'defaults to 1' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: nil,
          context: context
        )
        expect(result).to be true
      end
    end

    context 'when max_same_side is zero' do
      it 'defaults to 1' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 0,
          context: context
        )
        expect(result).to be true
      end
    end

    context 'when exactly 1 active position exists (pyramiding check)' do
      let(:existing_position) do
        instance_double(PositionTracker,
                        id: 1,
                        last_pnl_rupees: BigDecimal('500'),
                        updated_at: 10.minutes.ago,
                        entry_price: BigDecimal('150.0'),
                        quantity: 65,
                        current_pnl_rupees: 500)
      end
      let(:limit_with_one) { double('limit_one', count: 1, first: existing_position, to_a: [existing_position]) }

      before do
        allow(count_relation).to receive(:limit).with(3).and_return(limit_with_one)
        allow(existing_position).to receive(:reload)
        allow(existing_position).to receive(:hydrate_pnl_from_cache!)
      end

      context 'when pyramiding is allowed (positive PnL, old enough)' do
        it 'returns true' do
          result = described_class.exposure_ok?(
            instrument: instrument,
            side: 'long_ce',
            max_same_side: 2,
            context: context
          )
          expect(result).to be true
        end
      end

      context 'when pyramiding is not allowed (negative PnL)' do
        before do
          allow(existing_position).to receive(:last_pnl_rupees).and_return(BigDecimal('-100'))
        end

        it 'returns false' do
          result = described_class.exposure_ok?(
            instrument: instrument,
            side: 'long_ce',
            max_same_side: 2,
            context: context
          )
          expect(result).to be false
        end
      end

      context 'when nil last_pnl_rupees triggers calculate_current_pnl' do
        before do
          allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(1).and_return(nil)
          allow(existing_position).to receive(:update!)
          allow(Live::TickQuery).to receive(:for_security).and_return(nil)
          allow(existing_position).to receive_messages(last_pnl_rupees: nil, entry_price: BigDecimal('150.0'), quantity: 65, segment: 'NSE_FNO', security_id: '12345', exited?: false, high_water_mark_pnl: 0, tradable: nil)
        end

        it 'attempts to resolve LTP for PnL calculation' do
          described_class.exposure_ok?(
            instrument: instrument,
            side: 'long_ce',
            max_same_side: 2,
            context: context
          )
          expect(Live::TickQuery).to have_received(:for_security).with(segment: 'NSE_FNO', security_id: '12345')
        end
      end
    end

    context 'when no context is provided' do
      before do
        allow(active_relation).to receive(:where).with(side: anything).and_return(count_relation)
      end

      it 'works without context hash' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: nil
        )
        expect(result).to be true
      end
    end

    context 'when cache key exists in context' do
      before do
        context["exposure_check_101_long_ce"] = false
      end

      it 'returns cached result' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: context
        )
        expect(result).to be false
      end
    end

    context 'when multiple active positions exceed max_same_side' do
      let(:overflow_relation) { double('overflow_relation', count: 2) }

      before do
        allow(count_relation).to receive(:limit).with(3).and_return(overflow_relation)
      end

      it 'returns false' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: context
        )
        expect(result).to be false
      end
    end
  end

  describe 'private method: max_exposure_limit_for' do
    context 'when no risks config exists' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({})
      end

      it 'uses default value 0 (exposure check passes)' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: context
        )
        expect(result).to be true
      end
    end

    context 'when default exposure limit is set' do
      let(:over_limit_relation) do
        ar = double('over_limit')
        allow(ar).to receive(:sum).with('quantity * entry_price').and_return(600_000.0)
        ar
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ risk: { max_exposure_rupees: { default: 500_000 } } })
        allow(active_relation).to receive(:where).with(index_key: 'NIFTY').and_return(over_limit_relation)
        allow(count_relation).to receive(:limit).and_return(double('cl', count: 0))
      end

      it 'applies the default limit' do
        result = described_class.exposure_ok?(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2,
          context: context
        )
        expect(result).to be false
      end
    end
  end

  describe 'private method: active_supertrend_position?' do
    it 'blocks supertrend entry when active position exists' do
      allow(active_relation).to receive(:by_index_key).with('NIFTY').and_return(double('scope', exists?: true))

      context_with_supertrend = context.merge(
        entry_metadata: { entry_contract: 'supertrend_machine_v1' }
      )
      result = described_class.call(context_with_supertrend)
      expect(result).to include(blocked: /Supertrend/)
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
