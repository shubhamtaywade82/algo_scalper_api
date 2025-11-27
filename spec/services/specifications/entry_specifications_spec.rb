# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Specifications::EntryEligibilitySpecification do
  let(:instrument) { create(:instrument, :nifty_index) }
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: instrument.security_id,
      max_same_side: 2,
      cooldown_sec: 300
    }
  end
  let(:pick) do
    {
      symbol: 'NIFTY18500CE',
      security_id: '50074',
      segment: 'NSE_FNO',
      ltp: 100.0,
      lot_size: 75,
      expiry: 5.days.from_now.to_date
    }
  end
  let(:direction) { :bullish }

  let(:specification) do
    described_class.new(
      instrument: instrument,
      index_cfg: index_cfg,
      pick: pick,
      direction: direction
    )
  end

  before do
    allow(TradingSession::Service).to receive(:entry_allowed?).and_return({ allowed: true })
    allow(Live::DailyLimits.new).to receive(:can_trade?).and_return({ allowed: true })
    allow(Rails.cache).to receive(:read).and_return(nil)
  end

  describe '#initialize' do
    it 'sets instance variables' do
      expect(specification.instance_variable_get(:@instrument)).to eq(instrument)
      expect(specification.instance_variable_get(:@index_cfg)).to eq(index_cfg)
      expect(specification.instance_variable_get(:@pick)).to eq(pick)
      expect(specification.instance_variable_get(:@direction)).to eq(direction)
    end
  end

  describe '#satisfied?' do
    context 'when all specifications pass' do
      before do
        allow(PositionTracker).to receive(:active).and_return(double(where: double(count: 0)))
      end

      it 'returns true' do
        expect(specification.satisfied?(nil)).to be true
      end
    end

    context 'when trading session check fails' do
      before do
        allow(TradingSession::Service).to receive(:entry_allowed?).and_return(
          { allowed: false, reason: 'Market closed' }
        )
      end

      it 'returns false' do
        expect(specification.satisfied?(nil)).to be false
      end

      it 'provides failure reason' do
        expect(specification.failure_reason(nil)).to eq('Market closed')
      end
    end

    context 'when daily limit check fails' do
      before do
        allow(Live::DailyLimits.new).to receive(:can_trade?).and_return(
          { allowed: false, reason: 'Daily loss limit exceeded' }
        )
      end

      it 'returns false' do
        expect(specification.satisfied?(nil)).to be false
      end
    end

    context 'when exposure limit reached' do
      before do
        allow(PositionTracker).to receive(:active).and_return(
          double(where: double(count: 2, limit: double(count: 2)))
        )
      end

      it 'returns false' do
        expect(specification.satisfied?(nil)).to be false
      end
    end

    context 'when cooldown active' do
      before do
        allow(Rails.cache).to receive(:read).with("reentry:#{pick[:symbol]}").and_return(Time.current)
      end

      it 'returns false' do
        expect(specification.satisfied?(nil)).to be false
      end
    end

    context 'when LTP is invalid' do
      let(:invalid_pick) { pick.merge(ltp: nil) }

      it 'returns false' do
        invalid_spec = described_class.new(
          instrument: instrument,
          index_cfg: index_cfg,
          pick: invalid_pick,
          direction: direction
        )

        expect(invalid_spec.satisfied?(nil)).to be false
      end
    end

    context 'when expiry too far' do
      let(:far_expiry_pick) { pick.merge(expiry: 10.days.from_now.to_date) }

      it 'returns false' do
        far_expiry_spec = described_class.new(
          instrument: instrument,
          index_cfg: index_cfg,
          pick: far_expiry_pick,
          direction: direction
        )

        expect(far_expiry_spec.satisfied?(nil)).to be false
      end
    end
  end

  describe '#failure_reason' do
    context 'when specification fails' do
      before do
        allow(TradingSession::Service).to receive(:entry_allowed?).and_return(
          { allowed: false, reason: 'Market closed' }
        )
      end

      it 'returns first failure reason' do
        expect(specification.failure_reason(nil)).to eq('Market closed')
      end
    end

    context 'when all pass' do
      before do
        allow(PositionTracker).to receive(:active).and_return(double(where: double(count: 0)))
      end

      it 'returns nil' do
        expect(specification.failure_reason(nil)).to be_nil
      end
    end
  end

  describe '#all_failure_reasons' do
    before do
      allow(TradingSession::Service).to receive(:entry_allowed?).and_return(
        { allowed: false, reason: 'Market closed' }
      )
      allow(Live::DailyLimits.new).to receive(:can_trade?).and_return(
        { allowed: false, reason: 'Daily limit exceeded' }
      )
    end

    it 'returns all failure reasons' do
      reasons = specification.all_failure_reasons(nil)

      expect(reasons).to be_an(Array)
      expect(reasons.length).to be > 0
    end
  end

  describe 'individual specifications' do
    describe 'TradingSessionSpecification' do
      let(:spec) { Specifications::TradingSessionSpecification.new }

      it 'returns true when session allowed' do
        allow(TradingSession::Service).to receive(:entry_allowed?).and_return({ allowed: true })

        expect(spec.satisfied?(nil)).to be true
      end

      it 'returns false when session not allowed' do
        allow(TradingSession::Service).to receive(:entry_allowed?).and_return(
          { allowed: false, reason: 'Market closed' }
        )

        expect(spec.satisfied?(nil)).to be false
        expect(spec.failure_reason(nil)).to eq('Market closed')
      end
    end

    describe 'DailyLimitSpecification' do
      let(:spec) { Specifications::DailyLimitSpecification.new(index_key: 'NIFTY') }
      let(:daily_limits) { instance_double(Live::DailyLimits) }

      before do
        allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
      end

      it 'returns true when trading allowed' do
        allow(daily_limits).to receive(:can_trade?).and_return({ allowed: true })

        expect(spec.satisfied?(nil)).to be true
      end

      it 'returns false when limit exceeded' do
        allow(daily_limits).to receive(:can_trade?).and_return(
          { allowed: false, reason: 'Daily loss limit exceeded' }
        )

        expect(spec.satisfied?(nil)).to be false
      end
    end

    describe 'ExposureSpecification' do
      let(:spec) do
        Specifications::ExposureSpecification.new(
          instrument: instrument,
          side: 'long_ce',
          max_same_side: 2
        )
      end

      before do
        allow(PositionTracker).to receive(:active).and_return(
          double(where: double(count: 1, limit: double(count: 1)))
        )
      end

      it 'returns true when under limit' do
        expect(spec.satisfied?(nil)).to be true
      end

      it 'returns false when at limit' do
        allow(PositionTracker).to receive(:active).and_return(
          double(where: double(count: 2, limit: double(count: 2)))
        )

        expect(spec.satisfied?(nil)).to be false
      end
    end

    describe 'CooldownSpecification' do
      let(:spec) do
        Specifications::CooldownSpecification.new(
          symbol: 'NIFTY18500CE',
          cooldown_seconds: 300
        )
      end

      it 'returns true when no cooldown' do
        allow(Rails.cache).to receive(:read).and_return(nil)

        expect(spec.satisfied?(nil)).to be true
      end

      it 'returns false when cooldown active' do
        allow(Rails.cache).to receive(:read).and_return(Time.current)

        expect(spec.satisfied?(nil)).to be false
      end

      it 'returns true when cooldown expired' do
        allow(Rails.cache).to receive(:read).and_return(10.minutes.ago)

        expect(spec.satisfied?(nil)).to be true
      end
    end

    describe 'LtpSpecification' do
      it 'returns true for valid LTP' do
        spec = Specifications::LtpSpecification.new(ltp: BigDecimal('100.0'))

        expect(spec.satisfied?(nil)).to be true
      end

      it 'returns false for nil LTP' do
        spec = Specifications::LtpSpecification.new(ltp: nil)

        expect(spec.satisfied?(nil)).to be false
      end

      it 'returns false for zero LTP' do
        spec = Specifications::LtpSpecification.new(ltp: 0)

        expect(spec.satisfied?(nil)).to be false
      end
    end

    describe 'ExpirySpecification' do
      it 'returns true for valid expiry' do
        spec = Specifications::ExpirySpecification.new(
          expiry_date: 5.days.from_now.to_date,
          max_days: 7
        )

        expect(spec.satisfied?(nil)).to be true
      end

      it 'returns false for expiry too far' do
        spec = Specifications::ExpirySpecification.new(
          expiry_date: 10.days.from_now.to_date,
          max_days: 7
        )

        expect(spec.satisfied?(nil)).to be false
      end

      it 'returns true when expiry not provided' do
        spec = Specifications::ExpirySpecification.new(expiry_date: nil)

        expect(spec.satisfied?(nil)).to be true
      end
    end
  end
end
