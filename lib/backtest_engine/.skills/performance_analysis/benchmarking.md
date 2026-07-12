# Performance Benchmarking

Benchmark strategy performance against baseline indexes and random models.

## Benchmarks

1. **Random Signal Benchmark**:
   - Compare strategy results against a model that enters randomly and manages exits using identical trailing rules.
   - Assert strategy out-performs random entries with a $p\text{-value} < 0.05$.

2. **Static Target Benchmark**:
   - Compare strategy performance against a fixed target (e.g. exit at 1.5R or 2.0R) to verify if the trailing stop model is adding value.

3. **Index Buy & Hold Benchmark**:
   - Compare net returns against simply buying and holding the underlying index ETF.
