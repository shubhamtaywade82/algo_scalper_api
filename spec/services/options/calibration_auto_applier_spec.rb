# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationAutoApplier do
  let(:run) do
    CalibrationRun.create!(
      symbol: 'NIFTY',
      weeks_analyzed: 52,
      strike_mode: 'atm_only',
      raw_stats: { 'weeks_available' => 52 },
      proposed_patch: { 'risk' => { 'trailing' => { 'drawdown_pct' => 0.04 } } },
      is_regime_shift: false
    )
  end

  def stub_config(auto_apply:, paper: true)
    allow(AlgoConfig).to receive(:fetch).and_return(
      {
        paper_trading: { enabled: paper },
        calibration: { auto_apply: auto_apply }
      }
    )
  end

  describe '.call' do
    context 'when master switch is off' do
      before do
        stub_config(auto_apply: { enabled: false, historical_weekly: true })
      end

      it 'does not apply and suppresses skip notifications' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
        expect(result.suppress_notification).to be(true)
        expect(run.reload.applied_at).to be_nil
      end
    end

    context 'when historical_weekly is off' do
      before do
        stub_config(auto_apply: { enabled: true, historical_weekly: false, require_paper_trading: false })
      end

      it 'does not apply for historical source' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
        expect(result.suppress_notification).to be(true)
      end
    end

    context 'when ai_trades is off' do
      before do
        stub_config(auto_apply: { enabled: true, ai_trades: false, require_paper_trading: false })
      end

      it 'does not apply for ai source' do
        result = described_class.call(run: run, source: :ai)
        expect(result.applied).to be(false)
        expect(result.suppress_notification).to be(true)
      end
    end

    context 'when require_paper_trading and not paper' do
      before do
        stub_config(
          auto_apply: {
            enabled: true,
            historical_weekly: true,
            require_paper_trading: true,
            cooldown_days_between_applies: 0
          },
          paper: false
        )
      end

      it 'does not apply' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
        expect(result.suppress_notification).to be(false)
      end
    end

    context 'when regime shift and reject_on_regime_shift' do
      before do
        run.update!(is_regime_shift: true, regime_reason: 'test shift')
        stub_config(
          auto_apply: {
            enabled: true,
            historical_weekly: true,
            reject_on_regime_shift: true,
            require_paper_trading: false,
            cooldown_days_between_applies: 0
          }
        )
      end

      it 'does not apply' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
      end
    end

    context 'when proposed_patch is empty' do
      before do
        run.update!(proposed_patch: {})
        stub_config(
          auto_apply: {
            enabled: true,
            historical_weekly: true,
            require_paper_trading: false,
            cooldown_days_between_applies: 0
          }
        )
      end

      it 'does not apply' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
      end
    end

    context 'when cooldown has not elapsed' do
      before do
        CalibrationRun.create!(
          symbol: 'NIFTY',
          weeks_analyzed: 4,
          strike_mode: 'atm_only',
          raw_stats: {},
          proposed_patch: { 'risk' => { 'trailing' => { 'drawdown_pct' => 0.03 } } },
          is_regime_shift: false,
          applied_at: 1.day.ago,
          applied_by: 'api'
        )
        stub_config(
          auto_apply: {
            enabled: true,
            historical_weekly: true,
            require_paper_trading: false,
            cooldown_days_between_applies: 7,
            min_weeks_analyzed: 1
          }
        )
      end

      it 'does not apply' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
        expect(result.reason).to include('cooldown')
      end
    end

    context 'when insufficient weekly expiries in raw_stats' do
      before do
        run.update!(raw_stats: { 'weeks_available' => 2 }, weeks_analyzed: 2)
        stub_config(
          auto_apply: {
            enabled: true,
            historical_weekly: true,
            require_paper_trading: false,
            cooldown_days_between_applies: 0,
            min_weeks_analyzed: 4
          }
        )
      end

      it 'does not apply' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(false)
        expect(result.reason).to include('insufficient history')
      end
    end

    context 'when AI dataset too small' do
      let(:ai_run) do
        CalibrationRun.create!(
          symbol: 'NIFTY',
          weeks_analyzed: 0,
          strike_mode: 'ai_calibration',
          raw_stats: { 'dataset_meta' => { 'total_trades' => 5 } },
          proposed_patch: { 'risk' => { 'sl_pct' => 0.09 } },
          is_regime_shift: false
        )
      end

      before do
        stub_config(
          auto_apply: {
            enabled: true,
            ai_trades: true,
            require_paper_trading: false,
            cooldown_days_between_applies: 0,
            min_ai_trades: 15
          }
        )
      end

      it 'does not apply' do
        result = described_class.call(run: ai_run, source: :ai)
        expect(result.applied).to be(false)
        expect(result.reason).to include('insufficient AI dataset')
      end
    end

    context 'when all gates pass' do
      before do
        Setting.put('algo_config_overrides', '{}')
        AlgoConfig.reset!
        stub_config(
          auto_apply: {
            enabled: true,
            historical_weekly: true,
            reject_on_regime_shift: true,
            require_paper_trading: false,
            cooldown_days_between_applies: 0,
            min_weeks_analyzed: 4
          }
        )
      end

      after do
        Setting.where(key: 'algo_config_overrides').delete_all
        AlgoConfig.reset!
      end

      it 'applies the run' do
        result = described_class.call(run: run, source: :historical)
        expect(result.applied).to be(true)
        expect(result.suppress_notification).to be(false)
        expect(run.reload.applied_at).to be_present
        expect(run.applied_by).to eq('auto_historical')
      end
    end
  end
end
