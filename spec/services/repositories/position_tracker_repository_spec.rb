# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Repositories::PositionTrackerRepository do
  let(:instrument) { create(:instrument, :nifty_index) }
  let(:segment) { 'NSE_FNO' }
  let(:security_id) { '12345' }

  describe '.find_active_by_segment_and_security' do
    let!(:active_tracker) do
      create(:position_tracker,
             instrument: instrument,
             segment: segment,
             security_id: security_id,
             status: 'active')
    end

    let!(:exited_tracker) do
      create(:position_tracker,
             instrument: instrument,
             segment: segment,
             security_id: security_id,
             status: 'exited')
    end

    it 'finds active tracker by segment and security_id' do
      result = described_class.find_active_by_segment_and_security(
        segment: segment,
        security_id: security_id
      )

      expect(result).to eq(active_tracker)
      expect(result.status).to eq('active')
    end

    it 'returns nil when no active tracker found' do
      result = described_class.find_active_by_segment_and_security(
        segment: 'INVALID',
        security_id: '99999'
      )

      expect(result).to be_nil
    end

    it 'handles string and symbol segment' do
      result1 = described_class.find_active_by_segment_and_security(
        segment: segment.to_sym,
        security_id: security_id
      )
      result2 = described_class.find_active_by_segment_and_security(
        segment: segment.to_s,
        security_id: security_id
      )

      expect(result1).to eq(active_tracker)
      expect(result2).to eq(active_tracker)
    end
  end

  describe '.find_by_order_no' do
    let!(:tracker) { create(:position_tracker, order_no: 'ORD123456') }

    it 'finds tracker by order number' do
      result = described_class.find_by_order_no('ORD123456')

      expect(result).to eq(tracker)
    end

    it 'returns nil when order not found' do
      result = described_class.find_by_order_no('INVALID')

      expect(result).to be_nil
    end
  end

  describe '.active_count_by_side' do
    before do
      create_list(:position_tracker, 3, :active, side: 'long_ce', instrument: instrument)
      create_list(:position_tracker, 2, :active, side: 'long_pe', instrument: instrument)
      create_list(:position_tracker, 1, :exited, side: 'long_ce', instrument: instrument)
    end

    it 'counts active positions by side' do
      expect(described_class.active_count_by_side(side: 'long_ce')).to eq(3)
      expect(described_class.active_count_by_side(side: 'long_pe')).to eq(2)
    end
  end

  describe '.find_active_by_instrument' do
    let!(:trackers) do
      create_list(:position_tracker, 2, :active, instrument: instrument)
    end

    let!(:other_tracker) do
      other_instrument = create(:instrument)
      create(:position_tracker, :active, instrument: other_instrument)
    end

    it 'finds active positions for instrument' do
      result = described_class.find_active_by_instrument(instrument)

      expect(result.count).to eq(2)
      expect(result).to all(satisfy { |t| t.instrument_id == instrument.id })
      expect(result).to all(satisfy { |t| t.status == 'active' })
    end
  end

  describe '.find_active_by_index_key' do
    let!(:tracker1) do
      create(:position_tracker, :active, meta: { index_key: 'NIFTY' })
    end

    let!(:tracker2) do
      create(:position_tracker, :active, meta: { index_key: 'BANKNIFTY' })
    end

    it 'finds active positions by index key' do
      result = described_class.find_active_by_index_key('NIFTY')

      expect(result.count).to eq(1)
      expect(result.first).to eq(tracker1)
    end
  end

  describe '.find_by_status' do
    before do
      create_list(:position_tracker, 2, :active)
      create_list(:position_tracker, 3, :exited)
      create_list(:position_tracker, 1, :pending)
    end

    it 'finds positions by status' do
      expect(described_class.find_by_status(:active).count).to eq(2)
      expect(described_class.find_by_status(:exited).count).to eq(3)
      expect(described_class.find_by_status(:pending).count).to eq(1)
    end

    it 'handles string status' do
      expect(described_class.find_by_status('active').count).to eq(2)
    end
  end

  describe '.find_paper_positions' do
    before do
      create_list(:position_tracker, 2, paper: true)
      create_list(:position_tracker, 3, paper: false)
    end

    it 'finds paper trading positions' do
      result = described_class.find_paper_positions

      expect(result.count).to eq(2)
      expect(result).to all(satisfy { |t| t.paper == true })
    end
  end

  describe '.find_live_positions' do
    before do
      create_list(:position_tracker, 2, paper: true)
      create_list(:position_tracker, 3, paper: false)
    end

    it 'finds live trading positions' do
      result = described_class.find_live_positions

      expect(result.count).to eq(3)
      expect(result).to all(satisfy { |t| t.paper == false })
    end
  end

  describe '.exists_for_segment_and_security?' do
    before do
      create(:position_tracker,
             segment: segment,
             security_id: security_id,
             status: 'active')
    end

    it 'returns true when active position exists' do
      expect(described_class.exists_for_segment_and_security?(
        segment: segment,
        security_id: security_id
      )).to be true
    end

    it 'returns false when no active position' do
      expect(described_class.exists_for_segment_and_security?(
        segment: 'INVALID',
        security_id: '99999'
      )).to be false
    end
  end

  describe '.active_count' do
    before do
      create_list(:position_tracker, 5, :active)
      create_list(:position_tracker, 3, :exited)
    end

    it 'returns count of active positions' do
      expect(described_class.active_count).to eq(5)
    end
  end

  describe '.find_profitable_above' do
    before do
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('1000.00'))
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('500.00'))
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('100.00'))
    end

    it 'finds positions with PnL above threshold' do
      result = described_class.find_profitable_above(BigDecimal('200.00'))

      expect(result.count).to eq(2)
      expect(result).to all(satisfy { |t| t.last_pnl_rupees.to_f > 200.0 })
    end
  end

  describe '.find_losses_below' do
    before do
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('-1000.00'))
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('-500.00'))
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('-100.00'))
    end

    it 'finds positions with losses below threshold' do
      result = described_class.find_losses_below(BigDecimal('-200.00'))

      expect(result.count).to eq(2)
      expect(result).to all(satisfy { |t| t.last_pnl_rupees.to_f < -200.0 })
    end
  end

  describe '.find_by_date_range' do
    let(:start_date) { 2.days.ago }
    let(:end_date) { 1.day.ago }

    before do
      create(:position_tracker, created_at: 3.days.ago)
      create(:position_tracker, created_at: 1.5.days.ago)
      create(:position_tracker, created_at: 0.5.days.ago)
    end

    it 'finds positions within date range' do
      result = described_class.find_by_date_range(
        start_date: start_date,
        end_date: end_date
      )

      expect(result.count).to eq(1)
    end
  end

  describe '.statistics' do
    before do
      create_list(:position_tracker, 3, :active, paper: true)
      create_list(:position_tracker, 2, :active, paper: false)
      create_list(:position_tracker, 4, :exited, paper: true)
      create_list(:position_tracker, 1, :cancelled)
    end

    it 'returns comprehensive statistics' do
      stats = described_class.statistics

      expect(stats[:total]).to eq(10)
      expect(stats[:active]).to eq(5)
      expect(stats[:exited]).to eq(4)
      expect(stats[:cancelled]).to eq(1)
      expect(stats[:paper]).to eq(7)
      expect(stats[:live]).to eq(3)
    end

    it 'calculates total and average PnL' do
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('1000.00'))
      create(:position_tracker, :active, last_pnl_rupees: BigDecimal('2000.00'))

      stats = described_class.statistics(scope: PositionTracker.active)

      expect(stats[:total_pnl]).to be > 0
      expect(stats[:avg_pnl]).to be > 0
    end

    context 'with custom scope' do
      it 'returns statistics for scope' do
        paper_scope = PositionTracker.paper
        stats = described_class.statistics(scope: paper_scope)

        expect(stats[:total]).to eq(7)
        expect(stats[:paper]).to eq(7)
      end
    end
  end
end
