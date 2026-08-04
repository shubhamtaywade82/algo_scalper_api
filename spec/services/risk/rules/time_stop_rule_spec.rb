# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TimeStopRule do
  let(:tracker) do
    instance_double(
      PositionTracker,
      active?: true,
      created_at: 10.minutes.ago,
      entry_strategy: 'alpha_scalp',
      entry_path: 'scalp',
      meta: {},
      index_key: 'NIFTY',
      watchable: double('watchable', expiry_date: Date.current),
      underlying_instrument: double('instrument', symbol_name: 'NIFTY')
    )
  end

  let(:context) do
    Risk::Rules::RuleContext.new(
      position: OpenStruct.new(pnl_pct: 0.05),
      tracker: tracker,
      risk_config: {
        time_stop: {
          enabled: true,
          scalp: { max_minutes: 8 },
          trend: { NIFTY: 20 }
        }
      }
    )
  end

  let(:rule) { described_class.new(config: {}) }

  describe '#evaluate' do
    context 'when 0-DTE scalp trade' do
      it 'triggers time stop when elapsed time exceeds dynamic DTE-scaled limit (minimum floor)' do
        # 0-DTE means scale_factor = 0, so allowed is minimum floor (3 minutes / 180 seconds)
        # tracker is created 10 minutes ago, so elapsed (600s) > allowed (180s)
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.reason).to eq('TIME_STOP')
        expect(result.metadata[:allowed_seconds]).to eq(180.0)
      end

      it 'does not exit if elapsed time is below the floor' do
        allow(tracker).to receive(:created_at).and_return(1.minute.ago)
        result = rule.evaluate(context)
        expect(result).to be_no_action
      end
    end

    context 'when weekly DTE (7 days) trend trade' do
      before do
        allow(tracker).to receive_messages(
          entry_strategy: 'trend_buying',
          entry_path: 'trend',
          watchable: double('watchable', expiry_date: 7.days.from_now.to_date)
        )
      end

      it 'scalesallowed time stop to exactly the base limit (20 minutes)' do
        # 7-DTE means scale_factor = 7 / 7 = 1.0, allowed = 20 minutes (1200 seconds)
        # tracker is 10 minutes ago (600s), so elapsed (600s) < allowed (1200s)
        result = rule.evaluate(context)
        expect(result).to be_no_action
      end

      it 'exits when elapsed time exceeds scaled limit' do
        allow(tracker).to receive(:created_at).and_return(25.minutes.ago)
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.reason).to eq('TIME_STOP')
        expect(result.metadata[:allowed_seconds]).to eq(1200.0)
      end
    end

    context 'when watchable expiry_date is blank/invalid' do
      before do
        allow(tracker).to receive_messages(
          entry_strategy: 'trend_buying',
          entry_path: 'trend',
          watchable: double('watchable', expiry_date: Date.new(1))
        )
      end

      it 'falls back to 7 DTE and uses base limit' do
        # tracker is 10 minutes ago (600s), fallback 7-DTE => scale=1 => allowed=1200s
        result = rule.evaluate(context)
        expect(result).to be_no_action

        # Force exceed to confirm fallback DTE produced the expected allowed window
        allow(tracker).to receive(:created_at).and_return(25.minutes.ago)
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.reason).to eq('TIME_STOP')
        expect(result.metadata[:allowed_seconds]).to eq(1200.0)
      end
    end
  end
end
