# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::ExpiryWeekPowerTrendGuard do
  subject(:result) { described_class.call(context) }

  let(:expiry_4_days_out) { Time.zone.today + 4 }
  let(:expiry_30_days_out) { Time.zone.today + 30 }
  let(:instrument) { instance_double(Instrument, expiry_list: [expiry_4_days_out.to_s]) }
  let(:context) do
    {
      index_cfg: { key: 'BANKNIFTY' },
      pick: { adx_value: 53.0 },
      instrument: instrument,
      entry_metadata: {}
    }
  end

  let(:enabled_config) do
    {
      expiry_week_power_trend: {
        enabled: true,
        adx_min: 40,
        expiry_days_max: 5,
        entry_start: '12:00',
        entry_end: '13:45'
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(enabled_config)
  end

  # Freeze ALL time sources (Time.current AND Time.zone.today), not just
  # Time.current: the guard's expiry-week check reads Time.zone.today for
  # the last-Thursday fallback, so a Time.current-only stub left the test
  # date-dependent — it failed whenever the real calendar date happened to
  # fall within 5 days of a month's last Thursday (e.g. 2026-10-24 vs
  # 2026-10-29). Deterministic with travel_to, which stubs both.
  def stub_time(time_str)
    travel_to Time.zone.parse("2026-03-30 #{time_str} IST")
  end

  context 'when all conditions are met' do
    before { stub_time('12:30') }

    it 'returns PASS and sets expiry_power_trend on context' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be(true)
      expect(context[:entry_metadata][:expiry_power_trend]).to be(true)
    end
  end

  context 'when config is disabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        expiry_week_power_trend: { enabled: false }
      )
      stub_time('12:30')
    end

    it 'passes without enriching context' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end
  end

  context 'when outside entry window' do
    it 'passes without enriching context (before window)' do
      stub_time('11:45')
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end

    it 'passes without enriching context (after window)' do
      stub_time('14:00')
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end
  end

  context 'when ADX is below threshold' do
    before do
      stub_time('12:30')
      context[:pick][:adx_value] = 24.0
    end

    it 'passes without enriching context' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end
  end

  context 'when ADX is exactly at threshold' do
    before do
      stub_time('12:30')
      context[:pick][:adx_value] = 40.0
    end

    it 'sets expiry_power_trend' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be(true)
    end
  end

  context 'when not in expiry week' do
    before do
      stub_time('12:30')
      allow(instrument).to receive(:expiry_list).and_return([expiry_30_days_out.to_s])
    end

    it 'passes without enriching context' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end
  end

  context 'when instrument is nil (no expiry list available)' do
    before do
      stub_time('12:30')
      context[:instrument] = nil
    end

    it 'passes without enriching context (cannot confirm expiry week)' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end
  end

  context 'when expiry is today (0 days out)' do
    before do
      stub_time('12:30')
      allow(instrument).to receive(:expiry_list).and_return([Time.zone.today.to_s])
    end

    it 'sets expiry_power_trend (same-day expiry qualifies)' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be(true)
    end
  end

  context 'when ADX value is missing from pick' do
    before do
      stub_time('12:30')
      context[:pick] = {}
    end

    it 'passes without enriching context' do
      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(context[:expiry_power_trend]).to be_nil
    end
  end
end
