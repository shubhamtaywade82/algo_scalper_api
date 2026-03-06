# Indicator Threshold Configuration Guide

## Overview

The indicator system supports **adjustable thresholds** that can be loosened for testing and tightened based on results. This allows you to:

1. **Start loose** - Generate more signals to test the system
2. **Analyze results** - See which signals work
3. **Tighten gradually** - Improve signal quality based on performance

## Quick Start

### Option 1: Environment Variable (Recommended for Testing)

```bash
# Set loose thresholds for testing
export INDICATOR_PRESET=loose

# Run your tests
bundle exec rails runner "Signal::Engine.run_for(...)"

# Later, tighten for production
export INDICATOR_PRESET=tight
```

### Option 2: Configuration File

Edit `config/algo.yml`:

```yaml
signals:
  indicator_preset: loose  # Change to: moderate, tight, or production
```

## Available Presets

### 1. **LOOSE** - Very Permissive (Testing Phase)

**Use when:** Initial testing, want to see many signals

```yaml
indicator_preset: loose
```

**Settings:**
- ADX min_strength: **10** (very low - allows weak trends)
- RSI oversold: **40**, overbought: **60** (less strict)
- Multi-indicator min_confidence: **40** (low threshold)
- Confirmation mode: **any** (most permissive)

**Result:** Generates many signals, good for initial testing and data collection

### 2. **MODERATE** - Balanced (Default)

**Use when:** Starting point, balanced approach

```yaml
indicator_preset: moderate
```

**Settings:**
- ADX min_strength: **15**
- RSI oversold: **35**, overbought: **65**
- Multi-indicator min_confidence: **50**
- Confirmation mode: **majority**

**Result:** Balanced signal generation

### 3. **TIGHT** - Strict (Quality Focus)

**Use when:** Want fewer but higher quality signals

```yaml
indicator_preset: tight
```

**Settings:**
- ADX min_strength: **25** (only strong trends)
- RSI oversold: **25**, overbought: **75** (extreme levels)
- Multi-indicator min_confidence: **70** (high threshold)
- Confirmation mode: **all** (all indicators must agree)

**Result:** Fewer signals but higher probability

### 4. **PRODUCTION** - Optimized

**Use when:** After backtesting and optimization

```yaml
indicator_preset: production
```

**Settings:**
- ADX min_strength: **20**
- RSI oversold: **30**, overbought: **70**
- Multi-indicator min_confidence: **60**
- Confirmation mode: **all**

**Result:** Optimized based on historical performance

## Preset Comparison Table

| Setting | Loose | Moderate | Tight | Production |
|---------|-------|----------|-------|------------|
| **ADX min_strength** | 10 | 15 | 25 | 20 |
| **RSI oversold** | 40 | 35 | 25 | 30 |
| **RSI overbought** | 60 | 65 | 75 | 70 |
| **Multi min_confidence** | 40 | 50 | 70 | 60 |
| **Confirmation mode** | any | majority | all | all |
| **Signal Frequency** | High | Medium | Low | Optimized |
| **Signal Quality** | Lower | Balanced | Higher | Optimized |

## Workflow: Testing → Production

### Phase 1: Initial Testing (LOOSE)

```yaml
# config/algo.yml
signals:
  indicator_preset: loose
```

**Goal:** Generate many signals to test system functionality

**What to track:**
- Signal generation rate
- System stability
- Basic signal quality

### Phase 2: Analysis (MODERATE)

```yaml
signals:
  indicator_preset: moderate
```

**Goal:** Balanced testing with moderate thresholds

**What to track:**
- Win rate by indicator combination
- Which indicators work best together
- Optimal confirmation modes

### Phase 3: Optimization (TIGHT)

```yaml
signals:
  indicator_preset: tight
```

**Goal:** Focus on high-quality signals

**What to track:**
- Signal quality metrics
- False positive rate
- Profitability per signal

### Phase 4: Production (PRODUCTION)

```yaml
signals:
  indicator_preset: production
```

**Goal:** Deploy optimized settings

**What to track:**
- Live performance vs backtest
- Continuous optimization

## Custom Thresholds

You can override preset values in `config/algo.yml`:

```yaml
signals:
  indicator_preset: moderate  # Base preset
  indicators:
    - type: adx
      enabled: true
      config:
        min_strength: 18  # Override preset value (15) with custom value
    - type: rsi
      enabled: true
      config:
        oversold: 32  # Override preset value (35) with custom value
        overbought: 68  # Override preset value (65) with custom value
```

**Priority:** Custom config values > Preset values > Default values

## Per-Indicator Thresholds

### ADX Indicator

```yaml
- type: adx
  config:
    min_strength: 18  # Lower = more signals, Higher = fewer but stronger
    # Preset values: loose=10, moderate=15, tight=25, production=20
```

**Adjustment guide:**
- **Lower** (10-15): More signals, includes weak trends
- **Medium** (15-20): Balanced
- **Higher** (20-25): Fewer signals, only strong trends

### RSI Indicator

```yaml
- type: rsi
  config:
    oversold: 30   # Lower = triggers more often (more bullish signals)
    overbought: 70 # Higher = triggers more often (more bearish signals)
    # Preset values:
    #   loose: oversold=40, overbought=60
    #   moderate: oversold=35, overbought=65
    #   tight: oversold=25, overbought=75
    #   production: oversold=30, overbought=70
```

**Adjustment guide:**
- **Oversold**: Lower = more bullish signals (e.g., 25-30 = very oversold)
- **Overbought**: Higher = more bearish signals (e.g., 75-80 = very overbought)

### Multi-Indicator Strategy

```yaml
signals:
  min_confidence: 60  # Combined confidence threshold
  confirmation_mode: all  # all, majority, weighted, any
  # Preset values:
  #   loose: min_confidence=40, mode=any
  #   moderate: min_confidence=50, mode=majority
  #   tight: min_confidence=70, mode=all
  #   production: min_confidence=60, mode=all
```

**Adjustment guide:**
- **min_confidence**: Lower = more signals, Higher = fewer but higher quality
- **confirmation_mode**: 
  - `any` = most permissive (any indicator can confirm)
  - `majority` = balanced (50%+ must agree)
  - `all` = strictest (all must agree)

## Programmatic Access

```ruby
# Get current preset
preset = Indicators::ThresholdConfig.current_preset
# => :moderate

# Get thresholds for specific indicator
adx_thresholds = Indicators::ThresholdConfig.for_indicator(:adx, :loose)
# => { min_strength: 10, confidence_base: 40 }

# Get all available presets
presets = Indicators::ThresholdConfig.available_presets
# => [:loose, :moderate, :tight, :production]

# Merge with custom config
config = Indicators::ThresholdConfig.merge_with_thresholds(:adx, { period: 14 }, :tight)
# => { period: 14, min_strength: 25, confidence_base: 60 }
```

## Testing Strategy

### Step 1: Start with LOOSE

```bash
export INDICATOR_PRESET=loose
# Run for 1-2 weeks, collect data
```

**Metrics to track:**
- Total signals generated
- Signal distribution by indicator
- Basic win rate

### Step 2: Analyze Results

```ruby
# Query signals with confluence data
signals = TradingSignal.where("created_at > ?", 1.week.ago)
signals.each do |signal|
  confluence = signal.metadata['confluence']
  puts "Confluence: #{confluence['score']}% (#{confluence['strength']})"
end
```

**Questions to answer:**
- Which indicator combinations have highest win rate?
- What confluence scores correlate with profitability?
- Which indicators disagree most often?

### Step 3: Tighten Gradually

```yaml
# Move to moderate
indicator_preset: moderate

# Then to tight
indicator_preset: tight

# Finally to production (optimized)
indicator_preset: production
```

### Step 4: Custom Optimization

Based on analysis, create custom thresholds:

```yaml
signals:
  indicator_preset: production  # Base
  indicators:
    - type: adx
      config:
        min_strength: 22  # Custom optimized value
    - type: rsi
      config:
        oversold: 28  # Custom optimized value
  min_confidence: 65  # Custom optimized value
```

## Monitoring and Adjustment

### Track These Metrics

1. **Signal Generation Rate**
   - Loose: Expect 20-50 signals/day
   - Moderate: Expect 10-20 signals/day
   - Tight: Expect 3-10 signals/day

2. **Confluence Scores**
   - Track average confluence score
   - Signals with >80% confluence should have higher win rate

3. **Win Rate by Preset**
   - Compare win rates across presets
   - Find optimal balance

4. **False Positive Rate**
   - Track signals that didn't work
   - Adjust thresholds to reduce false positives

### Adjustment Guidelines

**If too many signals:**
- Increase `min_confidence`
- Switch to stricter `confirmation_mode` (majority → all)
- Increase ADX `min_strength`
- Tighten RSI levels

**If too few signals:**
- Decrease `min_confidence`
- Switch to more permissive `confirmation_mode` (all → majority)
- Decrease ADX `min_strength`
- Loosen RSI levels

**If signals are low quality:**
- Increase `min_confidence`
- Require stronger confluence (use `tight` preset)
- Add more indicators for confirmation

## Examples

### Example 1: Very Permissive Testing

```yaml
signals:
  indicator_preset: loose
  use_multi_indicator_strategy: true
  confirmation_mode: any  # Most permissive
  min_confidence: 30  # Very low threshold
```

### Example 2: Balanced Production

```yaml
signals:
  indicator_preset: production
  use_multi_indicator_strategy: true
  confirmation_mode: all
  min_confidence: 60
```

### Example 3: Custom Optimized

```yaml
signals:
  indicator_preset: production  # Base
  use_multi_indicator_strategy: true
  confirmation_mode: majority
  min_confidence: 65  # Custom value
  indicators:
    - type: adx
      config:
        min_strength: 22  # Custom optimized
    - type: rsi
      config:
        oversold: 28  # Custom optimized
        overbought: 72
```

## Best Practices

1. **Start Loose**: Begin with `loose` preset to test system
2. **Collect Data**: Run for sufficient time to gather statistics
3. **Analyze Results**: Use confluence data to understand indicator behavior
4. **Tighten Gradually**: Move from loose → moderate → tight → production
5. **Custom Optimize**: Fine-tune based on your specific market conditions
6. **Monitor Continuously**: Track performance and adjust as needed

## Troubleshooting

**Q: No signals generated?**
- Check if preset is too tight
- Try `loose` preset first
- Verify indicators are enabled

**Q: Too many signals?**
- Switch to `tight` preset
- Increase `min_confidence`
- Use stricter `confirmation_mode`

**Q: Signals not profitable?**
- Check confluence scores (aim for >70%)
- Analyze which indicators work best
- Tighten thresholds gradually
