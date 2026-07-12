# Bias Detection Protocols

This document defines the protocols used by the auditor to detect and reject historical backtesting biases.

## 1. Lookahead Bias
* **Detection**: Insert automated assertions into the data provider. If the strategy requests `candles[i+1]` or future metrics, flag a critical failure.
* **Remedy**: Re-index the indicator series to ensure values are computed using only past records.

## 2. Curve Fitting (Overfitting)
* **Detection**: Check if small parameter variations (e.g. changing an EMA lookback from 20 to 19 or 21) result in massive drops in profit.
* **Remedy**: Apply parameter smoothing or reject the strategy.

## 3. Data Leakage
* **Detection**: Check if the indicator engine uses out-of-sample data during in-sample calculations (e.g., using a global standard deviation instead of rolling standard deviation).
* **Remedy**: Enforce strict boundary partitions between training/in-sample and testing/out-of-sample segments.

## 4. Calendar / Expiry Bias
* **Detection**: Check if all strategy profit is concentrated on a single weekday (e.g. Wednesday expiry) or during a specific monthly expiry week.
* **Remedy**: Run sub-segment reports by weekday and expiry week to isolate calendar anomalies.
