# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::CarryPolicy do
  describe '.carry_allowed?' do
    context 'when positional mode is off' do
      before do
        allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(false)
      end

      it 'returns false' do
        expect(described_class.carry_allowed?(index_key: 'NIFTY')).to be(false)
      end
    end

    context 'when positional mode is on and DTE is at least 1' do
      before do
        allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
        allow(OptionsBuying::Mode).to receive(:config).and_return({ positional: { require_carry_allowed: true } })
        analyzer = instance_double(Options::DerivativeChainAnalyzer, find_nearest_expiry: Time.zone.today + 2)
        allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(analyzer)
      end

      it 'returns true' do
        expect(described_class.carry_allowed?(index_key: 'NIFTY')).to be(true)
      end
    end

    context 'when today is expiry day' do
      before do
        allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
        analyzer = instance_double(Options::DerivativeChainAnalyzer, find_nearest_expiry: Time.zone.today)
        allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(analyzer)
      end

      it 'returns false' do
        expect(described_class.carry_allowed?(index_key: 'NIFTY')).to be(false)
      end
    end
  end

  describe '.min_carry_roi' do
    it 'reads the configured decimal threshold' do
      allow(OptionsBuying::Mode).to receive(:config).and_return({ positional: { min_carry_roi: 0.4 } })
      expect(described_class.min_carry_roi).to eq(0.4)
    end

    it 'defaults to 0.30 when unset' do
      allow(OptionsBuying::Mode).to receive(:config).and_return({})
      expect(described_class.min_carry_roi).to eq(0.30)
    end
  end

  describe '.carry_eligible?' do
    let(:tracker) { build(:position_tracker, segment: 'NSE_FNO', last_pnl_pct: roi).tap { |t| t.index_key = 'NIFTY' } }

    before do
      allow(OptionsBuying::Mode).to receive(:config).and_return({})
      allow(described_class).to receive(:carry_allowed?) do |args|
        args[:index_key] == 'NIFTY' ? carry_allowed : false
      end
    end

    context 'when carry allowed and ROI clears the threshold' do
      let(:carry_allowed) { true }
      let(:roi) { BigDecimal('0.45') }

      it { expect(described_class.carry_eligible?(tracker)).to be(true) }
    end

    context 'when ROI is below the threshold' do
      let(:carry_allowed) { true }
      let(:roi) { BigDecimal('0.10') }

      it { expect(described_class.carry_eligible?(tracker)).to be(false) }
    end

    context 'when carry is not allowed' do
      let(:carry_allowed) { false }
      let(:roi) { BigDecimal('0.90') }

      it { expect(described_class.carry_eligible?(tracker)).to be(false) }
    end

    context 'when tracker has no index_key' do
      let(:carry_allowed) { true }
      let(:roi) { BigDecimal('0.90') }

      it 'returns false' do
        tracker.index_key = nil
        expect(described_class.carry_eligible?(tracker)).to be(false)
      end
    end
  end

  describe '.carried? and .carry_still_valid?' do
    let(:tracker) { build(:position_tracker, segment: 'NSE_FNO').tap { |t| t.index_key = 'NIFTY' } }

    it 'carried? reflects the carry_mode tag' do
      expect(described_class.carried?(tracker)).to be(false)
      tracker.carry_mode = 'positional'
      expect(described_class.carried?(tracker)).to be(true)
    end

    it 'carry_still_valid? is false for untagged trackers without consulting carry_allowed?' do
      allow(described_class).to receive(:carry_allowed?)
      expect(described_class.carry_still_valid?(tracker)).to be(false)
      expect(described_class).not_to have_received(:carry_allowed?)
    end

    it 'carry_still_valid? holds a tagged carry while carry remains allowed' do
      tracker.carry_mode = 'positional'
      allow(described_class).to receive(:carry_allowed?).with(index_key: 'NIFTY').and_return(true)
      expect(described_class.carry_still_valid?(tracker)).to be(true)
    end

    it 'carry_still_valid? releases a tagged carry once carry lapses (e.g. expiry day)' do
      tracker.carry_mode = 'positional'
      allow(described_class).to receive(:carry_allowed?).with(index_key: 'NIFTY').and_return(false)
      expect(described_class.carry_still_valid?(tracker)).to be(false)
    end
  end
end
