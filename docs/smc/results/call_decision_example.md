# Call Decision Example

## Purpose
This example illustrates a `:call` decision. It uses the full hash shape
returned by `Smc::BiasEngine#details` with illustrative values only.

## Example Hash
```ruby
{
  decision: :call,
  timeframes: {
    htf: {
      interval: "60",
      context: {
        internal_structure: {
          trend: :bullish,
          bos: false,
          choch: false,
          swings: [
            { type: :low, price: 24_850.0 },
            { type: :high, price: 25_120.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :bullish,
          bos: true,
          choch: false,
          swings: [
            { type: :low, price: 24_720.0 },
            { type: :high, price: 25_200.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :bullish,
          bos: true,
          choch: false,
          swings: [
            { type: :low, price: 24_720.0 },
            { type: :high, price: 25_200.0 }
          ],
          lookback: 5,
          type: :swing
        },
        liquidity: {
          buy_side_taken: false,
          sell_side_taken: false,
          sweep_direction: nil,
          equal_highs: false,
          equal_lows: true,
          sweep: false
        },
        order_blocks: {
          bullish: {
            open: 24_910.0,
            high: 24_980.0,
            low: 24_880.0,
            close: 24_960.0,
            timestamp: "2026-01-17T09:00:00Z"
          },
          bearish: nil,
          internal: [
            { bias: :bullish, high: 24_980.0, low: 24_880.0, index: 52 }
          ],
          swing: [
            { bias: :bullish, high: 24_980.0, low: 24_880.0, index: 52 }
          ]
        },
        fvg: {
          gaps: [
            { type: :bullish, from: 24_840.0, to: 24_890.0 }
          ]
        },
        premium_discount: {
          high: 25_220.0,
          low: 24_680.0,
          equilibrium: 24_950.0,
          price: 24_890.0,
          premium: false,
          discount: true
        },
        trend: :bullish
      }
    },
    mtf: {
      interval: "15",
      context: {
        internal_structure: {
          trend: :bullish,
          bos: false,
          choch: false,
          swings: [
            { type: :low, price: 24_860.0 },
            { type: :high, price: 24_980.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :bullish,
          bos: false,
          choch: false,
          swings: [
            { type: :low, price: 24_820.0 },
            { type: :high, price: 25_020.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :bullish,
          bos: false,
          choch: false,
          swings: [
            { type: :low, price: 24_820.0 },
            { type: :high, price: 25_020.0 }
          ],
          lookback: 5,
          type: :swing
        },
        liquidity: {
          buy_side_taken: false,
          sell_side_taken: false,
          sweep_direction: nil,
          equal_highs: false,
          equal_lows: false,
          sweep: false
        },
        order_blocks: {
          bullish: nil,
          bearish: nil,
          internal: [],
          swing: []
        },
        fvg: {
          gaps: []
        },
        premium_discount: {
          high: 25_040.0,
          low: 24_790.0,
          equilibrium: 24_915.0,
          price: 24_895.0,
          premium: false,
          discount: true
        },
        trend: :bullish
      }
    },
    ltf: {
      interval: "5",
      context: {
        internal_structure: {
          trend: :bullish,
          bos: true,
          choch: true,
          swings: [
            { type: :low, price: 24_870.0 },
            { type: :high, price: 24_940.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :bullish,
          bos: true,
          choch: true,
          swings: [
            { type: :low, price: 24_840.0 },
            { type: :high, price: 24_960.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :bullish,
          bos: true,
          choch: true,
          swings: [
            { type: :low, price: 24_840.0 },
            { type: :high, price: 24_960.0 }
          ],
          lookback: 5,
          type: :swing
        },
        liquidity: {
          buy_side_taken: false,
          sell_side_taken: true,
          sweep_direction: :sell_side,
          equal_highs: false,
          equal_lows: true,
          sweep: true
        },
        order_blocks: {
          bullish: {
            open: 24_890.0,
            high: 24_930.0,
            low: 24_870.0,
            close: 24_920.0,
            timestamp: "2026-01-17T10:15:00Z"
          },
          bearish: nil,
          internal: [
            { bias: :bullish, high: 24_930.0, low: 24_870.0, index: 120 }
          ],
          swing: [
            { bias: :bullish, high: 24_930.0, low: 24_870.0, index: 120 }
          ]
        },
        fvg: {
          gaps: []
        },
        premium_discount: {
          high: 24_980.0,
          low: 24_830.0,
          equilibrium: 24_905.0,
          price: 24_910.0,
          premium: true,
          discount: false
        },
        trend: :bullish
      },
      avrz: {
        rejection: true,
        lookback: 20,
        min_wick_ratio: 1.8,
        min_vol_multiplier: 1.5
      }
    }
  }
}
```
