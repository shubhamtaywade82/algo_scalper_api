# Put Decision Example

## Purpose
This example illustrates a `:put` decision. It uses the full hash shape
returned by `Smc::BiasEngine#details` with illustrative values only.

## Example Hash
```ruby
{
  decision: :put,
  timeframes: {
    htf: {
      interval: "60",
      context: {
        internal_structure: {
          trend: :bearish,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_280.0 },
            { type: :low, price: 25_010.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :bearish,
          bos: true,
          choch: false,
          swings: [
            { type: :high, price: 25_310.0 },
            { type: :low, price: 24_980.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :bearish,
          bos: true,
          choch: false,
          swings: [
            { type: :high, price: 25_310.0 },
            { type: :low, price: 24_980.0 }
          ],
          lookback: 5,
          type: :swing
        },
        liquidity: {
          buy_side_taken: false,
          sell_side_taken: false,
          sweep_direction: nil,
          equal_highs: true,
          equal_lows: false,
          sweep: false
        },
        order_blocks: {
          bullish: nil,
          bearish: {
            open: 25_240.0,
            high: 25_290.0,
            low: 25_190.0,
            close: 25_210.0,
            timestamp: "2026-01-17T09:00:00Z"
          },
          internal: [
            { bias: :bearish, high: 25_290.0, low: 25_190.0, index: 48 }
          ],
          swing: [
            { bias: :bearish, high: 25_290.0, low: 25_190.0, index: 48 }
          ]
        },
        fvg: {
          gaps: [
            { type: :bearish, from: 25_220.0, to: 25_160.0 }
          ]
        },
        premium_discount: {
          high: 25_340.0,
          low: 24_880.0,
          equilibrium: 25_110.0,
          price: 25_270.0,
          premium: true,
          discount: false
        },
        trend: :bearish
      }
    },
    mtf: {
      interval: "15",
      context: {
        internal_structure: {
          trend: :bearish,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_210.0 },
            { type: :low, price: 25_110.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :bearish,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_240.0 },
            { type: :low, price: 25_080.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :bearish,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_240.0 },
            { type: :low, price: 25_080.0 }
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
          high: 25_260.0,
          low: 25_040.0,
          equilibrium: 25_150.0,
          price: 25_210.0,
          premium: true,
          discount: false
        },
        trend: :bearish
      }
    },
    ltf: {
      interval: "5",
      context: {
        internal_structure: {
          trend: :bearish,
          bos: true,
          choch: true,
          swings: [
            { type: :high, price: 25_200.0 },
            { type: :low, price: 25_120.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :bearish,
          bos: true,
          choch: true,
          swings: [
            { type: :high, price: 25_230.0 },
            { type: :low, price: 25_100.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :bearish,
          bos: true,
          choch: true,
          swings: [
            { type: :high, price: 25_230.0 },
            { type: :low, price: 25_100.0 }
          ],
          lookback: 5,
          type: :swing
        },
        liquidity: {
          buy_side_taken: true,
          sell_side_taken: false,
          sweep_direction: :buy_side,
          equal_highs: true,
          equal_lows: false,
          sweep: true
        },
        order_blocks: {
          bullish: nil,
          bearish: {
            open: 25_180.0,
            high: 25_220.0,
            low: 25_140.0,
            close: 25_150.0,
            timestamp: "2026-01-17T10:15:00Z"
          },
          internal: [
            { bias: :bearish, high: 25_220.0, low: 25_140.0, index: 118 }
          ],
          swing: [
            { bias: :bearish, high: 25_220.0, low: 25_140.0, index: 118 }
          ]
        },
        fvg: {
          gaps: []
        },
        premium_discount: {
          high: 25_240.0,
          low: 25_100.0,
          equilibrium: 25_170.0,
          price: 25_140.0,
          premium: false,
          discount: true
        },
        trend: :bearish
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
