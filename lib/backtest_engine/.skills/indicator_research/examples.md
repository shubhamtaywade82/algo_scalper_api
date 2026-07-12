# Indicator Research Examples

Here are concrete examples showing how the researcher validates indicators and calculates correlations.

## Example 1: Validating a 20-period EMA Implementation

### Math Verification
* Inputs: Close prices `[100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119]` (first 20 values).
* Reference value at index 19 (20th close): `109.5` (simple average baseline).
* Reference value at index 20 (close: 120): `EMA = (120 * (2/21)) + (109.5 * (19/21)) = 110.5`
* Class code outputs `110.5002`. Alignment checks pass within `1e-4` precision.

---

## Example 2: Detecting High Feature Correlation (Redundancy)

### Scenario
* Researcher runs a correlation sweep on three features:
  - **Feature A**: 20-period EMA distance to spot.
  - **Feature B**: 50-period EMA distance to spot.
  - **Feature C**: 20-period VWAP distance to spot.

### Results
* Correlation Matrix:
  - Correlation(Feature A, Feature B): `0.88`
  - Correlation(Feature A, Feature C): `0.92`
* Action:
  - Feature C is highly correlated to Feature A ($> 0.70$).
  - Feature C (VWAP distance) is marked as **redundant** and removed from the active strategy's feature vector to prevent collinearly-inflated models.
