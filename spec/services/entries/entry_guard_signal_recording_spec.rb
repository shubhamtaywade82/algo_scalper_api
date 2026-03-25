# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard, '#try_enter signal recording' do
  let(:signal) do
    create(:trading_signal,
           index_key: 'NIFTY',
           direction: 'bullish',
           timeframe: '1m',
           supertrend_value: 23440,
           adx_value: 20.4,
           candle_timestamp: 1.minute.ago,
           signal_timestamp: Time.current,
           metadata: {})
  end

  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'NSE_FNO',
      cooldown_sec: 0
    }
  end

  let(:pick) do
    { symbol: 'NIFTY26MAR23440CE', security_id: '12345', segment: 'NSE_FNO' }
  end

  describe 'when DrawdownGuard is triggered' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true)
    end

    it 'records skipped with drawdown_guard_active reason' do
      described_class.try_enter(
        index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: signal
      )

      expect(signal.reload.metadata['entry_outcome']).to eq('skipped')
      expect(signal.reload.metadata['entry_blocked_reason']).to eq('drawdown_guard_active')
    end
  end

  describe 'when EntryPolicy blocks' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
      policy_dbl = instance_double(Policies::EntryPolicy,
                                   permitted?: false,
                                   reasons: ['max_positions_reached', 'direction_locked'])
      allow(Policies::EntryPolicy).to receive(:new).and_return(policy_dbl)
    end

    it 'records blocked with joined policy reasons' do
      described_class.try_enter(
        index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: signal
      )

      expect(signal.reload.metadata['entry_outcome']).to eq('blocked')
      expect(signal.reload.metadata['entry_blocked_reason']).to eq('max_positions_reached; direction_locked')
    end
  end

  describe 'when a guard pipeline guard blocks' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
      policy_dbl = instance_double(Policies::EntryPolicy, permitted?: true)
      allow(Policies::EntryPolicy).to receive(:new).and_return(policy_dbl)
      allow(described_class.entry_guard_pipeline).to receive(:run).and_return(
        { blocked: 'cooldown active for index NIFTY' }
      )
    end

    it 'records blocked with the guard reason string' do
      described_class.try_enter(
        index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: signal
      )

      expect(signal.reload.metadata['entry_outcome']).to eq('blocked')
      expect(signal.reload.metadata['entry_blocked_reason']).to eq('cooldown active for index NIFTY')
    end
  end

  describe 'when no signal is passed' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true)
    end

    it 'does not raise when signal is nil' do
      expect {
        described_class.try_enter(
          index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: nil
        )
      }.not_to raise_error
    end
  end
end
