# Indicator Implementation Validation Guide

Before an indicator can be deployed, its code implementation must pass numerical alignment checks to ensure mathematical correctness.

## Alignment Verification

1. **Verify against Reference Libraries**:
   - Compare indicator output array against **TA-Lib** or **pandas-ta** using identical input data.
   - Assert that values align within a precision limit (e.g. `1e-5`).

2. **Warm-up Check**:
   - Verify that output values are correctly marked as `nil` or `NaN` during the warm-up window (e.g. first 20 candles of a 20-period EMA).
   - Ensure indicator does not access out-of-bounds indices.

3. **Lookahead / Data Leakage Check**:
   - Assert that for any index `i`, the indicator value at `i` is calculated strictly using inputs from index `0` up to `i` (or `i - 1` if using previous-period closes).
   - Any access to index `i + 1` or higher is lookahead bias and will fail verification.
