# Paper Trading System Design

## Overview

A complete paper trading system that uses live market data from DhanHQ (WebSocket feeds, OHLC data) but simulates order execution and position management locally without placing real orders through DhanHQ.

## Architecture

### Components

1. **PaperWallet** - Manages virtual capital
2. **PaperOrder** - Tracks simulated order execution
3. **PaperPosition** - Manages simulated position PnL
4. **PaperPlacer** - Service for placing simulated orders
5. **PaperRiskManager** - Manages paper trading PnL and exits
6. **PaperPerformanceReport** - Generates trading statistics

## Database Schema

### paper_wallets

```ruby
create_table :paper_wallets do |t|
  t.decimal :initial_capital, precision: 15, scale: 2, default: 0
  t.decimal :available_capital, precision: 15, scale: 2, default: 0
  t.decimal :invested_capital, precision: 15, scale: 2, default: 0
  t.decimal :total_pnl, precision: 15, scale: 2, default: 0
  t.string :mode, default: 'paper' # paper or live

  t.timestamps
end
```

### paper_orders

```ruby
create_table :paper_orders do |t|
  t.references :instrument, null: false, foreign_key: true
  t.string :order_no, null: false, unique: true
  t.string :correlation_id
  t.string :security_id, null: false
  t.string :segment, null: false
  t.string :symbol
  t.string :transaction_type, null: false # BUY, SELL
  t.string :order_type, default: 'MARKET'
  t.string :product_type, default: 'INTRADAY'
  t.integer :quantity, null: false
  t.decimal :price, precision: 15, scale: 2
  t.decimal :executed_price, precision: 15, scale: 2
  t.string :status, default: 'pending' # pending, executed, rejected, cancelled
  t.text :error_message
  t.jsonb :meta

  t.timestamps
  t.index :order_no
  t.index :security_id
  t.index :status
end
```

### paper_positions

```ruby
create_table :paper_positions do |t|
  t.references :instrument, null: false, foreign_key: true
  t.references :paper_order, null: false, foreign_key: true
  t.string :security_id, null: false
  t.string :symbol
  t.string :segment
  t.string :side, null: false # LONG, SHORT
  t.integer :quantity, null: false
  t.decimal :entry_price, precision: 15, scale: 2, null: false
  t.decimal :current_price, precision: 15, scale: 2
  t.decimal :pnl_rupees, precision: 15, scale: 2, default: 0
  t.decimal :pnl_percent, precision: 10, scale: 4, default: 0
  t.decimal :high_water_mark_pnl, precision: 15, scale: 2, default: 0
  t.string :status, default: 'active' # active, exited
  t.jsonb :meta

  t.timestamps
  t.index :security_id
  t.index :status
end
```

### paper_trades

```ruby
create_table :paper_trades do |t|
  t.references :paper_position, null: false, foreign_key: true
  t.references :paper_order, null: false, foreign_key: true
  t.decimal :entry_price, precision: 15, scale: 2, null: false
  t.decimal :exit_price, precision: 15, scale: 2, null: false
  t.decimal :pnl_rupees, precision: 15, scale: 2, default: 0
  t.decimal :pnl_percent, precision: 10, scale: 4, default: 0
  t.decimal :brokerage, precision: 10, scale: 2, default: 0
  t.decimal :net_pnl, precision: 15, scale: 2, default: 0
  t.datetime :entry_time
  t.datetime :exit_time
  t.integer :duration_seconds
  t.string :signal_source

  t.timestamps
end
```

## Services

### PaperPlacer (app/services/paper/placer.rb)

Handles simulated order placement.

```ruby
module Paper
  class Placer
    def self.buy_market!(seg:, sid:, qty:, client_order_id:, product_type: 'INTRADAY')
      # Create paper order
      # Execute immediately with current market price
      # Create paper position
      # Update wallet
    end

    def self.sell_market!(seg:, sid:, qty:, client_order_id:, product_type: 'INTRADAY')
      # Find matching position
      # Execute exit
      # Close position
      # Update wallet
    end

    def self.exit_position!(seg:, sid:, client_order_id:)
      # Find position and close it
    end
  end
end
```

### PaperRiskManager (app/services/paper/risk_manager.rb)

Manages PnL tracking and risk rules for paper positions.

```ruby
module Paper
  class RiskManager
    def self.update_all_positions!
      # Fetch all active paper positions
      # Update PnL using current market prices
      # Enforce stop-loss/take-profit
      # Update high-water marks
    end

    def self.enforce_trailing_stops!
      # Similar to live risk manager
    end
  end
end
```

### PaperPerformanceReport (app/services/paper/performance_report.rb)

Generates trading statistics.

```ruby
module Paper
  class PerformanceReport
    def self.generate!
      # Total PnL
      # Win rate
      # Average gain/loss
      # Best/worst trades
      # Drawdown
      # Sharpe ratio
    end
  end
end
```

## Integration Flow

1. **Signal Generation** - Uses live signals (unchanged)
2. **Entry Decision** - Uses live entry guards (unchanged)
3. **Order Placement** - Routes to PaperPlacer instead of Orders::Placer when in paper mode
4. **Market Data** - Uses same WebSocket feeds (unchanged)
5. **Risk Management** - Uses PaperRiskManager for simulated positions
6. **Performance Tracking** - PaperPerformanceReport generates stats

## Configuration

Add to `config/algo.yml`:

```yaml
paper_trading:
  enabled: true
  initial_capital: 100000 # 1 lakh
  brokerage_per_lot: 20
  stamp_duty_per_lot: 1
```

Environment variable:

```bash
PAPER_TRADING=true # enables paper mode
```

## Key Differences from Live Trading

| Aspect             | Live Trading     | Paper Trading      |
| ------------------ | ---------------- | ------------------ |
| Data Source        | DhanHQ WebSocket | Same WebSocket     |
| Order Execution    | DhanHQ API       | Simulated          |
| Position Tracking  | DhanHQ API       | Local DB           |
| Capital Management | Real money       | Virtual wallet     |
| PnL Calculation    | From DhanHQ      | Calculated locally |
| Performance Report | Not available    | Full report        |

## Advantages

1. **Safe Testing** - Test strategy without risking real money
2. **Complete Isolation** - No impact on live DhanHQ account
3. **Full Transparency** - All orders and positions tracked locally
4. **Performance Analysis** - Detailed statistics and reports
5. **Rapid Iteration** - Test changes quickly without broker limits

## Next Steps

1. Create database migrations
2. Implement PaperPlacer service
3. Implement PaperRiskManager service
4. Implement PaperPerformanceReport service
5. Create PaperWallet model
6. Create PaperOrder, PaperPosition, PaperTrade models
7. Add routing logic to switch between paper/live modes
8. Add API endpoint for performance reports
9. Create admin interface for paper trading dashboard
