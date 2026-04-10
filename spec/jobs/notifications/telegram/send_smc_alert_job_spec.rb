# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Telegram::SendSmcAlertJob do
  let(:job) { described_class.new }

  describe '#append_trend_mismatch_hint (via send)' do
    it 'adds a 5m hint when MTF swing matches MTF internal but LTF diverges' do
      reasons = []
      mtf = {
        swing_structure: { trend: :bullish },
        internal_structure: { trend: :bullish }
      }
      ltf = {
        swing_structure: { trend: :bearish },
        internal_structure: { trend: :bullish }
      }

      job.send(:append_trend_mismatch_hint, reasons, mtf, ltf)

      expect(reasons).to eq(['5m internal trend bullish vs swing trend bearish'])
    end

    it 'adds a 15m hint when MTF diverges and does not skip 5m when LTF also diverges' do
      reasons = []
      mtf = {
        swing_structure: { trend: :bullish },
        internal_structure: { trend: :bearish }
      }
      ltf = {
        swing_structure: { trend: :bullish },
        internal_structure: { trend: :bearish }
      }

      job.send(:append_trend_mismatch_hint, reasons, mtf, ltf)

      expect(reasons).to eq(
        [
          '15m internal trend bearish vs swing trend bullish',
          '5m internal trend bearish vs swing trend bullish'
        ]
      )
    end

    it 'adds nothing when both timeframes agree internally' do
      reasons = []
      mtf = { swing_structure: { trend: :bullish }, internal_structure: { trend: :bullish } }
      ltf = { swing_structure: { trend: :bullish }, internal_structure: { trend: :bullish } }

      job.send(:append_trend_mismatch_hint, reasons, mtf, ltf)

      expect(reasons).to be_empty
    end
  end

  describe '#build_reasons (via send)' do
    it 'omits AVRZ for no_trade but still records LTF trend mismatch' do
      contexts = {
        decision: 'no_trade',
        mtf: {
          swing_structure: { trend: :bullish },
          internal_structure: { trend: :bullish }
        },
        ltf: {
          swing_structure: { trend: :bearish },
          internal_structure: { trend: :bullish }
        }
      }

      reasons = job.send(:build_reasons, contexts, decision: 'no_trade')

      expect(reasons).to include('5m internal trend bullish vs swing trend bearish')
      expect(reasons).not_to include('AVRZ rejection confirmed')
    end

    it 'includes AVRZ for call decisions' do
      contexts = { decision: 'call', mtf: {}, ltf: {} }

      reasons = job.send(:build_reasons, contexts, decision: 'call')

      expect(reasons).to include('AVRZ rejection confirmed')
    end
  end
end
