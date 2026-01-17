# No Trade Decision Example

## Purpose
This example illustrates a `:no_trade` decision. It uses the full hash shape
returned by `Smc::BiasEngine#details` with illustrative values only.

## Example Hash
```ruby
{
  decision: :no_trade,
  timeframes: {
    htf: {
      interval: "60",
      context: {
        internal_structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_080.0 },
            { type: :low, price: 24_990.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_120.0 },
            { type: :low, price: 24_960.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_120.0 },
            { type: :low, price: 24_960.0 }
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
          high: 25_140.0,
          low: 24_940.0,
          equilibrium: 25_040.0,
          price: 25_040.0,
          premium: false,
          discount: false
        },
        trend: :range
      }
    },
    mtf: {
      interval: "15",
      context: {
        internal_structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_040.0 },
            { type: :low, price: 25_000.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_060.0 },
            { type: :low, price: 24_980.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_060.0 },
            { type: :low, price: 24_980.0 }
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
          high: 25_080.0,
          low: 24_960.0,
          equilibrium: 25_020.0,
          price: 25_010.0,
          premium: false,
          discount: true
        },
        trend: :range
      }
    },
    ltf: {
      interval: "5",
      context: {
        internal_structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_010.0 },
            { type: :low, price: 24_990.0 }
          ],
          lookback: 2,
          type: :internal
        },
        swing_structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_020.0 },
            { type: :low, price: 24_980.0 }
          ],
          lookback: 5,
          type: :swing
        },
        structure: {
          trend: :range,
          bos: false,
          choch: false,
          swings: [
            { type: :high, price: 25_020.0 },
            { type: :low, price: 24_980.0 }
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
          low: 24_970.0,
          equilibrium: 25_005.0,
          price: 25_000.0,
          premium: false,
          discount: true
        },
        trend: :range
      },
      avrz: {
        rejection: false,
        lookback: 20,
        min_wick_ratio: 1.8,
        min_vol_multiplier: 1.5
      }
    }
  }
}
```
