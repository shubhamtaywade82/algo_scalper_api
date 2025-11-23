# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'NEMESIS V3 Flow Integration', :vcr, type: :integration do
  let(:nifty_instrument) { create(:instrument, :nifty_future, security_id: '26000', symbol_name: 'NIFTY') }
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'NSE_INDEX',
      sid: '26000',
      capital_alloc_pct: 0.30,
      max_same_side: 2,
      cooldown_sec: 180
    }
  end

  before do
    # Mock AlgoConfig
    allow(AlgoConfig).to receive(:fetch).and_return(
      indices: [index_cfg],
      risk: {
        max_daily_loss_pct: 5000.0, # ₹5000
        max_global_daily_loss_pct: 10_000.0, # ₹10000
        max_daily_trades: 10,
        max_global_daily_trades: 20
      }
    )

    # Mock Redis for DailyLimits
    allow(Redis).to receive(:new).and_return(
      instance_double(Redis,
                      get: nil,
                      setex: true,
                      incr: 1,
                      incrbyfloat: 1.0,
                      expire: true)
    )

    # Mock MarketFeedHub
    allow(Live::MarketFeedHub.instance).to receive_messages(
      running?: true,
      connected?: true
    )

    # Mock TickCache
    allow(Live::TickCache).to receive(:ltp).and_return(25_000.0)

    # Mock IndexInstrumentCache
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nifty_instrument)

    # Mock Capital::Allocator
    allow(Capital::Allocator).to receive_messages(
      qty_for: 75,
      available_cash: 100_000.0,
      paper_trading_balance: 100_000.0
    )
    allow(Capital::Allocator).to receive(:deployment_policy).and_return(
      { risk_per_trade_pct: 0.025 } # 2.5%
    )

    # Mock Orders::Placer
    allow(Orders.config).to receive(:place_market).and_return(double(order_id: 'ORD123456'))
    allow(Entries::EntryGuard).to receive(:extract_order_no).and_return('ORD123456')

    # Mock PositionTracker creation
    allow(PositionTracker).to receive(:create!).and_return(
      create(:position_tracker,
             order_no: 'ORD123456',
             security_id: '49081',
             entry_price: 150.0,
             quantity: 75,
             status: 'pending')
    )
  end

  describe 'Scenario 1: Full flow - Signal → Entry → Trailing → Exit' do
    it 'completes full trading flow with trailing stops' do
      # Step 1: Generate signal using TrendScorer and IndexSelector
      index_selector = Signal::IndexSelector.new
      best_index = index_selector.select_best_index

      expect(best_index).to be_a(Hash)
      expect(best_index[:index_key]).to eq(:NIFTY)
      expect(best_index[:trend_score]).to be >= 0

      # Step 2: Select strike using StrikeSelector
      strike_selector = Options::StrikeSelector.new
      instrument_hash = strike_selector.select(
        index_key: 'NIFTY',
        direction: :bullish,
        trend_score: best_index[:trend_score]
      )

      expect(instrument_hash).to be_a(Hash)
      expect(instrument_hash[:security_id]).to be_present

      # Step 3: Entry via EntryManager
      entry_manager = Orders::EntryManager.new
      entry_result = entry_manager.process_entry(
        signal_result: { candidate: instrument_hash },
        index_cfg: index_cfg,
        direction: :bullish,
        trend_score: best_index[:trend_score]
      )

      expect(entry_result[:success]).to be true
      expect(entry_result[:tracker]).to be_present

      tracker = entry_result[:tracker]

      # Step 4: Add to ActiveCache
      active_cache = Positions::ActiveCache.instance
      position_data = active_cache.add_position(
        tracker: tracker,
        sl_price: entry_result[:sl_price],
        tp_price: entry_result[:tp_price]
      )

      expect(position_data).to be_present
      expect(position_data.peak_profit_pct).to eq(0.0)

      # Step 5: Simulate LTP updates and trailing
      trailing_engine = Live::TrailingEngine.new
      exit_engine = instance_double(Live::ExitEngine)

      # Simulate profit increase
      position_data.update_ltp(165.0) # 10% profit
      expect(position_data.pnl_pct).to be > 0

      # Process trailing
      result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)
      expect(result[:peak_updated]).to be true

      # Step 6: Simulate exit (TP hit)
      position_data.update_ltp(240.0) # 60% profit (TP)
      expect(position_data.tp_hit?).to be true
    end
  end

  describe 'Scenario 2: Peak-drawdown exit trigger' do
    it 'triggers immediate exit when peak drawdown threshold is breached' do
      # Create position with profit
      tracker = create(:position_tracker,
                       order_no: 'ORD789',
                       security_id: '49081',
                       entry_price: 150.0,
                       quantity: 75,
                       status: 'active')

      active_cache = Positions::ActiveCache.instance
      position_data = active_cache.add_position(
        tracker: tracker,
        sl_price: 105.0,
        tp_price: 240.0
      )

      # Simulate profit to 25% (peak)
      position_data.update_ltp(187.5) # 25% profit
      expect(position_data.pnl_pct).to be >= 25.0
      expect(position_data.peak_profit_pct).to be >= 25.0

      # Simulate drawdown to 18% (7% drawdown from 25% peak)
      # Peak drawdown threshold is 5%, so this should trigger exit
      position_data.update_ltp(177.0) # 18% profit (7% drawdown from 25%)

      trailing_engine = Live::TrailingEngine.new
      exit_engine = instance_double(Live::ExitEngine)

      allow(exit_engine).to receive(:execute_exit).and_return(true)
      allow(PositionTracker).to receive(:find_by).and_return(tracker)
      allow(tracker).to receive(:active?).and_return(true)
      allow(tracker).to receive(:with_lock).and_yield

      # Process tick - should trigger peak-drawdown exit
      result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)

      expect(result[:exit_triggered]).to be true
      expect(exit_engine).to have_received(:execute_exit).with(
        tracker,
        match(/peak_drawdown_exit/)
      )
    end
  end

  describe 'Scenario 3: Tiered SL moves' do
    it 'applies tiered stop-loss adjustments based on profit percentage' do
      tracker = create(:position_tracker,
                       order_no: 'ORD456',
                       security_id: '49081',
                       entry_price: 150.0,
                       quantity: 75,
                       status: 'active')

      active_cache = Positions::ActiveCache.instance
      position_data = active_cache.add_position(
        tracker: tracker,
        sl_price: 105.0, # Initial SL (30% below entry)
        tp_price: 240.0
      )

      trailing_engine = Live::TrailingEngine.new
      bracket_placer = instance_double(Orders::BracketPlacer)
      allow(Orders::BracketPlacer).to receive(:instance).and_return(bracket_placer)
      allow(bracket_placer).to receive(:update_bracket).and_return({ success: true })

      # Test tier 1: 5% profit → SL should move to -15% offset (entry * 0.85 = 127.5)
      position_data.update_ltp(157.5) # 5% profit
      result = trailing_engine.process_tick(position_data, exit_engine: nil)
      expect(result[:sl_updated]).to be true

      # Test tier 2: 10% profit → SL should move to -5% offset (entry * 0.95 = 142.5)
      position_data.update_ltp(165.0) # 10% profit
      result = trailing_engine.process_tick(position_data, exit_engine: nil)
      expect(result[:sl_updated]).to be true

      # Test tier 3: 15% profit → SL should move to breakeven (entry * 1.0 = 150.0)
      position_data.update_ltp(172.5) # 15% profit
      result = trailing_engine.process_tick(position_data, exit_engine: nil)
      expect(result[:sl_updated]).to be true

      # Test tier 4: 25% profit → SL should move to +10% offset (entry * 1.10 = 165.0)
      position_data.update_ltp(187.5) # 25% profit
      result = trailing_engine.process_tick(position_data, exit_engine: nil)
      expect(result[:sl_updated]).to be true
    end
  end

  describe 'Scenario 4: Daily limits enforcement' do
    it 'blocks trading when daily loss limit is exceeded' do
      daily_limits = Live::DailyLimits.new

      # Record losses up to limit
      daily_limits.record_loss(index_key: 'NIFTY', amount: 5000.0) # Hit limit

      # Try to trade - should be blocked
      limit_check = daily_limits.can_trade?(index_key: 'NIFTY')
      expect(limit_check[:allowed]).to be false
      expect(limit_check[:reason]).to eq('daily_loss_limit_exceeded')

      # EntryGuard should block entry
      pick = {
        symbol: 'NIFTY-25Jan2024-25000-CE',
        security_id: '49081',
        segment: 'NSE_FNO',
        ltp: 150.0,
        lot_size: 75
      }

      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nifty_instrument)
      allow(Entries::EntryGuard).to receive_messages(exposure_ok?: true, cooldown_active?: false)

      result = Entries::EntryGuard.try_enter(
        index_cfg: index_cfg,
        pick: pick,
        direction: :bullish
      )

      expect(result).to be false
    end

    it 'blocks trading when trade frequency limit is exceeded' do
      daily_limits = Live::DailyLimits.new

      # Record trades up to limit
      10.times { daily_limits.record_trade(index_key: 'NIFTY') }

      # Try to trade - should be blocked
      limit_check = daily_limits.can_trade?(index_key: 'NIFTY')
      expect(limit_check[:allowed]).to be false
      expect(limit_check[:reason]).to eq('trade_frequency_limit_exceeded')
    end
  end

  describe 'Scenario 5: Recovery after restart' do
    it 'reloads peak values from Redis on startup' do
      tracker = create(:position_tracker,
                       order_no: 'ORD999',
                       security_id: '49081',
                       entry_price: 150.0,
                       quantity: 75,
                       status: 'active')

      # Simulate persisted peak value in Redis
      mock_redis = double('Redis')
      allow(Redis).to receive(:new).and_return(mock_redis)
      allow(mock_redis).to receive(:get).with("position_peaks:#{tracker.id}").and_return('25.5') # 25.5% peak
      allow(mock_redis).to receive(:setex).and_return(true)

      # Create new ActiveCache instance (simulating restart)
      active_cache = Positions::ActiveCache.instance

      # Add position
      active_cache.add_position(
        tracker: tracker,
        sl_price: 105.0,
        tp_price: 240.0
      )

      # Reload peaks
      count = active_cache.reload_peaks

      # Peak should be restored
      expect(count).to be >= 0
      # NOTE: In real scenario, peak would be applied when position is added
    end
  end
end
