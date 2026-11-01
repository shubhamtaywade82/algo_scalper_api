# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketBriefReport do
  let(:now) { Time.find_zone('Asia/Kolkata').local(2026, 10, 27, 10, 31, 20) }

  describe '.request!' do
    it 'collapses repeated manual requests in one slot onto one report' do
      first, created = described_class.request!(mode: :paper, now: now)
      again, created_again = described_class.request!(mode: :paper, now: now + 2.minutes)

      expect(created).to be(true)
      expect(created_again).to be(false)
      expect(again.id).to eq(first.id)
      expect(first).to have_attributes(status: 'pending', ai_status: 'pending', trading_date: Date.new(2026, 10, 27),
                                       schema_version: 1)
    end

    it 'opens a new report in the next slot and keeps modes separate' do
      first, = described_class.request!(mode: :paper, now: now)
      next_slot, = described_class.request!(mode: :paper, now: now + 6.minutes)
      live, = described_class.request!(mode: :live, now: now)

      expect([next_slot.id, live.id]).not_to include(first.id)
    end

    it 'uses one scheduled report per 15-minute slot and mode' do
      first, = described_class.request!(mode: :paper, trigger: 'scheduled', now: now)
      same, = described_class.request!(mode: :paper, trigger: 'scheduled', now: now + 10.minutes)
      later, = described_class.request!(mode: :paper, trigger: 'scheduled', now: now + 16.minutes)

      expect(first.report_key).to start_with('2026-10-27:paper:s')
      expect(same.id).to eq(first.id)
      expect(later.id).not_to eq(first.id)
    end

    it 'resolves a unique-index race to the winning row' do
      winner, = described_class.request!(mode: :paper, now: now)
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      allow(described_class).to receive_messages(find_by: nil, find_by!: winner)

      expect(described_class.request!(mode: :paper, now: now)).to eq([winner, false])
    end
  end

  describe '#claim_for_build!' do
    it 'lets exactly one caller claim a pending report' do
      report, = described_class.request!(mode: :paper, now: now)
      other = described_class.find(report.id)

      expect(report.claim_for_build!).to be(true)
      expect(other.claim_for_build!).to be(false)
      expect(report.reload.status).to eq('building')
    end

    it 'allows reclaiming a build stuck past the timeout' do
      report, = described_class.request!(mode: :paper, now: now)
      report.update_columns(status: 'building', updated_at: 11.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      expect(report.claim_for_build!).to be(true)
    end

    it 'never reclaims a ready report' do
      report, = described_class.request!(mode: :paper, now: now)
      report.update!(status: 'ready')
      expect(report.claim_for_build!).to be(false)
    end
  end

  describe '#as_api_json' do
    it 'hides AI analysis unless the AI stage completed' do
      report, = described_class.request!(mode: :paper, now: now)
      report.update!(ai_status: 'invalid', ai_analysis: { 'executive_summary' => 'x' })
      expect(report.as_api_json[:ai]).to include(status: 'invalid', analysis: nil)
    end
  end

  describe 'event trigger' do
    it 'creates a separate report for each event, even within the same millisecond' do
      first, created_first = described_class.request!(mode: :paper, trigger: 'event', now: now, reasons: ['a'])
      second, created_second = described_class.request!(mode: :paper, trigger: 'event', now: now, reasons: ['b'])

      expect([created_first, created_second]).to eq([true, true])
      expect(second.id).not_to eq(first.id)
      expect(second.report_key).to start_with('2026-10-27:paper:e')
    end

    it 'stores the change descriptions, bounded in count and length' do
      reasons = Array.new(10) { |i| "change #{i} #{'x' * 400}" }
      report, = described_class.request!(mode: :paper, trigger: 'event', now: now, reasons: reasons)

      expect(report.trigger_reasons.size).to eq(described_class::MAX_TRIGGER_REASONS)
      expect(report.trigger_reasons.first.length).to be <= 240
    end

    it 'exposes the reasons through the API representation' do
      report, = described_class.request!(mode: :paper, trigger: 'event', now: now, reasons: ['NIFTY regime changed'])
      expect(report.as_api_json).to include(trigger: 'event', trigger_reasons: ['NIFTY regime changed'])
    end

    it 'keeps scheduled and manual keys unchanged' do
      scheduled, = described_class.request!(mode: :paper, trigger: 'scheduled', now: now)
      manual, = described_class.request!(mode: :paper, trigger: 'manual', now: now)

      expect(scheduled.report_key).to end_with(":s#{now.to_i / 900 * 900}")
      expect(manual.report_key).to end_with(":m#{now.to_i / 300 * 300}")
    end
  end
end
