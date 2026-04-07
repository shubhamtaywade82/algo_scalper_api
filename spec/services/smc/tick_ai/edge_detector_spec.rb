# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::TickAi::EdgeDetector do
  let(:ltf) { '5' }

  def digest_for(ltf_long: false, ltf_short: false)
    {
      'alignment' => {
        'long_signal' => { '5' => ltf_long, '15' => false },
        'short_signal' => { '5' => ltf_short, '15' => false },
        'choch_bull' => { '5' => false },
        'choch_bear' => { '5' => false },
        'liq_sweep_bull' => { '5' => false },
        'liq_sweep_bear' => { '5' => false },
        'pdh_sweep' => { '5' => false },
        'pdl_sweep' => { '5' => false }
      }
    }
  end

  describe '.evaluate' do
    context 'when previous snapshot is empty' do
      it 'marks bootstrap and does not fire' do
        d = digest_for(ltf_long: true)
        r = described_class.evaluate(digest: d, ltf_interval: ltf, previous_snapshot: {})
        expect(r.bootstrap).to be(true)
        expect(r.fired_keys).to eq([])
        expect(r.current['long_signal']).to be(true)
      end
    end

    context 'when long_signal rises' do
      it 'fires long_signal' do
        prev = described_class.extract_flags(digest_for(ltf_long: false), ltf)
        d = digest_for(ltf_long: true)
        r = described_class.evaluate(digest: d, ltf_interval: ltf, previous_snapshot: prev)
        expect(r.bootstrap).to be(false)
        expect(r.fired_keys).to eq(['long_signal'])
      end
    end

    context 'when long_signal stays true' do
      it 'does not fire again' do
        prev = described_class.extract_flags(digest_for(ltf_long: true), ltf)
        d = digest_for(ltf_long: true)
        r = described_class.evaluate(digest: d, ltf_interval: ltf, previous_snapshot: prev)
        expect(r.fired_keys).to eq([])
      end
    end
  end
end
