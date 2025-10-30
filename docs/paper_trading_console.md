# Paper Trading Console Commands

When `PAPER_MODE=true`, you can use the following commands to view paper trading status.

## Rake Tasks

### View Wallet Balance
```bash
bin/rails paper:wallet
```

Output:
```
============================================================
  PAPER TRADING WALLET
============================================================
  Cash Available:  ₹100000.00
  Unrealized P&L:  ₹2500.50
  Total Equity:    ₹102500.50
  Total Exposure:  ₹35000.00
============================================================
```

### View Active Positions
```bash
bin/rails paper:positions
```

Shows all active positions with:
- Symbol and Security ID
- Quantity and entry price
- Current LTP
- Unrealized P&L
- Realized P&L
- Order number

### Complete Status (Wallet + Positions)
```bash
bin/rails paper:status
```

Shows both wallet and positions in one view.

## Rails Console Helpers

When in Rails console (`rails console`), you can use these helper methods:

### `paper_wallet`
Shows wallet balance:
```ruby
paper_wallet
# => Returns wallet snapshot hash
```

### `paper_positions`
Lists all active positions:
```ruby
paper_positions
# => Returns array of position hashes
```

### `paper_status`
Shows complete status:
```ruby
paper_status
# => Shows wallet + positions summary
```

### `paper_position(security_id, segment: 'NSE_FNO')`
Get details for a specific position:
```ruby
paper_position('50058')
# or
paper_position('50058', segment: 'NSE_FNO')
```

## API Endpoints (when server is running)

### GET `/api/paper/wallet`
Returns JSON wallet snapshot:
```json
{
  "cash": 100000.0,
  "equity": 102500.5,
  "mtm": 2500.5,
  "exposure": 35000.0,
  "timestamp": 1698123456
}
```

### GET `/api/paper/position?segment=NSE_FNO&security_id=50058`
Returns JSON position snapshot:
```json
{
  "segment": "NSE_FNO",
  "security_id": "50058",
  "qty": 35,
  "avg_price": 427.0,
  "upnl": 250.5,
  "rpnl": 0.0,
  "last_ltp": 434.15,
  "timestamp": 1698123456
}
```

## Notes

- All commands require `PAPER_MODE=true` to work
- Position data is stored in Redis
- Wallet is initialized with `PAPER_SEED_CASH` (default: ₹100,000)
- Positions are automatically tracked via `PositionTracker` model


