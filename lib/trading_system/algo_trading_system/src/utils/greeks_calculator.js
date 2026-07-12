// frozen_string_literal: true

// Greeks Calculator & Real-Time Signal Processor
// Used in conjunction with DhanHQ WebSocket for live trading

const fs = require('fs');

/**
 * Black-Scholes Greeks Calculator
 */
class GreeksCalculator {
  constructor(riskFreeRate = 0.06) {
    this.riskFreeRate = riskFreeRate;
  }

  /**
   * Calculate all Greeks for an option
   * 
   * @param {number} spot Spot Price
   * @param {number} strike Strike Price
   * @param {number} expiry Days to Expiry
   * @param {number} volatility Implied Volatility (as percentage, e.g., 35 for 35%)
   * @param {string} optionType 'CALL' or 'PUT'
   * @param {number} dividend Dividend yield (as percentage, e.g., 0)
   * @returns {Object} Calculated Greeks
   */
  calculateGreeks(spot, strike, expiry, volatility, optionType = 'CALL', dividend = 0) {
    if (!this.validateInputs(spot, strike, expiry, volatility)) {
      return null;
    }

    const T = expiry / 365.0; // Time to expiry in years
    const S = spot;
    const K = strike;
    const r = this.riskFreeRate;
    const sigma = volatility / 100.0; // Convert percentage to decimal
    const q = dividend / 100.0;

    // d1 and d2 calculations
    const d1 = (Math.log(S / K) + (r - q + 0.5 * sigma * sigma) * T) / (sigma * Math.sqrt(T));
    const d2 = d1 - sigma * Math.sqrt(T);

    // Cumulative normal distribution
    const nd1 = this.normalCDF(d1);
    const nd2 = this.normalCDF(d2);
    const pdf_d1 = this.normalPDF(d1);

    // Greeks calculation
    const delta = optionType === 'CALL' 
      ? Math.exp(-q * T) * nd1 
      : Math.exp(-q * T) * (nd1 - 1);

    const gamma = (Math.exp(-q * T) * pdf_d1) / (S * sigma * Math.sqrt(T));

    const vega = S * Math.exp(-q * T) * pdf_d1 * Math.sqrt(T) / 100.0; // Per 1% change

    const theta = optionType === 'CALL'
      ? (-S * Math.exp(-q * T) * pdf_d1 * sigma / (2 * Math.sqrt(T)) 
        - r * K * Math.exp(-r * T) * nd2 
        + q * S * Math.exp(-q * T) * nd1) / 365.0
      : (-S * Math.exp(-q * T) * pdf_d1 * sigma / (2 * Math.sqrt(T)) 
        + r * K * Math.exp(-r * T) * (1 - nd2) 
        - q * S * Math.exp(-q * T) * (1 - nd1)) / 365.0;

    const rho = optionType === 'CALL'
      ? K * T * Math.exp(-r * T) * nd2 / 100.0
      : -K * T * Math.exp(-r * T) * (1 - nd2) / 100.0;

    return {
      delta: Math.round(delta * 1000) / 1000,
      gamma: Math.round(gamma * 100000) / 100000,
      vega: Math.round(vega * 1000) / 1000,
      theta: Math.round(theta * 100) / 100,
      rho: Math.round(rho * 100) / 100,
      calculated_at: new Date().toISOString()
    };
  }

  /**
   * Estimate IV from option price (Newton-Raphson method)
   */
  estimateIV(spot, strike, expiry, optionPrice, optionType = 'CALL', maxIterations = 10) {
    if (!this.validateInputs(spot, strike, expiry, 20)) {
      return null;
    }

    let iv = 0.20; // Initial guess
    const S = spot;
    const K = strike;
    const T = expiry / 365.0;
    const r = this.riskFreeRate;

    for (let i = 0; i < maxIterations; i++) {
      const price = this.blackScholesPrice(S, K, T, r, iv, optionType);
      const greeks = this.calculateGreeks(S, K, expiry, iv * 100, optionType);
      const vega = greeks ? greeks.vega : 0;

      if (Math.abs(price - optionPrice) < 0.01 || vega === 0) {
        break;
      }

      iv -= (price - optionPrice) / (vega * 100);
      iv = Math.max(0.01, Math.min(5.0, iv)); // Clamp between 1% and 500%
    }

    return Math.round(iv * 100 * 100) / 100; // Return as percentage
  }

  /**
   * Black-Scholes price calculation
   */
  blackScholesPrice(spot, strike, T, r, sigma, optionType = 'CALL') {
    const d1 = (Math.log(spot / strike) + (r + 0.5 * sigma * sigma) * T) / (sigma * Math.sqrt(T));
    const d2 = d1 - sigma * Math.sqrt(T);

    if (optionType === 'CALL') {
      return spot * this.normalCDF(d1) - strike * Math.exp(-r * T) * this.normalCDF(d2);
    } else {
      return strike * Math.exp(-r * T) * this.normalCDF(-d2) - spot * this.normalCDF(-d1);
    }
  }

  /**
   * Normal CDF (cumulative distribution function)
   */
  normalCDF(x) {
    return (1.0 + this.erf(x / Math.sqrt(2))) / 2.0;
  }

  /**
   * Normal PDF (probability density function)
   */
  normalPDF(x) {
    return Math.exp(-x * x / 2.0) / Math.sqrt(2 * Math.PI);
  }

  /**
   * Error function approximation (Abramowitz and Stegun)
   */
  erf(x) {
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    const sign = x < 0 ? -1 : 1;
    x = Math.abs(x);

    const t = 1.0 / (1.0 + p * x);
    const y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);

    return sign * y;
  }

  /**
   * Input validation
   */
  validateInputs(spot, strike, expiry, volatility) {
    if (spot <= 0 || strike <= 0 || expiry < 0 || volatility <= 0) {
      return false;
    }
    return true;
  }
}

/**
 * Real-time Signal Processor
 */
class SignalProcessor {
  constructor(greeksCalculator) {
    this.greeksCalculator = greeksCalculator;
    this.marketData = new Map(); // Cache for market data
  }

  /**
   * Process market update and generate trade signals
   */
  processMarketUpdate(update) {
    const {
      symbol,
      spot,
      optionLTP,
      strike,
      optionType,
      expiryDays,
      iv,
      volume,
      openInterest,
      timestamp
    } = update;

    // Calculate Greeks
    const greeks = this.greeksCalculator.calculateGreeks(
      spot,
      strike,
      expiryDays,
      iv,
      optionType
    );

    if (!greeks) {
      return { signal: 'INVALID', reason: 'Greeks calculation failed' };
    }

    // Cache market data
    this.marketData.set(symbol, {
      spot,
      optionLTP,
      strike,
      optionType,
      expiryDays,
      iv,
      volume,
      openInterest,
      greeks,
      timestamp
    });

    // Generate signals based on Greeks and market conditions
    return this.generateSignal(symbol, greeks, {
      spot,
      optionLTP,
      iv,
      volume,
      openInterest,
      expiryDays
    });
  }

  /**
   * Generate trading signal
   */
  generateSignal(symbol, greeks, marketData) {
    const signals = [];
    const { delta, gamma, vega, theta } = greeks;
    const { spot, optionLTP, iv, volume, openInterest, expiryDays } = marketData;

    // Signal 1: Theta decay opportunity (short expiry, high decay)
    if (expiryDays <= 2 && Math.abs(theta) > 0.5) {
      signals.push({
        type: 'THETA_DECAY',
        action: 'HOLD_IF_SHORT',
        confidence: 8,
        reason: `High theta decay (${theta.toFixed(3)}) with ${expiryDays} days to expiry`
      });
    }

    // Signal 2: Delta neutral opportunity (low delta near ATM)
    if (Math.abs(delta) < 0.2 && Math.abs(gamma) > 0.005) {
      signals.push({
        type: 'DELTA_NEUTRAL',
        action: 'BUY',
        confidence: 7,
        reason: `Low delta (${delta.toFixed(3)}) + high gamma (${gamma.toFixed(5)}): straddle opportunity`
      });
    }

    // Signal 3: IV crush opportunity
    if (iv > 40 && volume > 1000 && openInterest > 5000) {
      signals.push({
        type: 'IV_CRUSH',
        action: 'SELL_PREMIUM',
        confidence: 8,
        reason: `High IV (${iv.toFixed(1)}%) with strong volume/OI: expect contraction`
      });
    }

    // Signal 4: Momentum entry (high delta, high volume)
    if (Math.abs(delta) > 0.65 && volume > 2000) {
      signals.push({
        type: 'MOMENTUM',
        action: 'BUY',
        confidence: 7,
        reason: `High delta momentum (${Math.abs(delta).toFixed(2)}) with volume surge`
      });
    }

    // Signal 5: Gamma squeeze (low price, high gamma)
    if (optionLTP < (Math.abs(spot - strike) * 0.05) && gamma > 0.01) {
      signals.push({
        type: 'GAMMA_SQUEEZE',
        action: 'BUY',
        confidence: 6,
        reason: `OTM but high gamma (${gamma.toFixed(4)}): asymmetric payoff`
      });
    }

    // Return primary signal (highest confidence)
    if (signals.length === 0) {
      return { signal: 'HOLD', confidence: 0, reason: 'No signals generated' };
    }

    const primarySignal = signals.sort((a, b) => b.confidence - a.confidence)[0];
    return {
      signal: primarySignal.action,
      type: primarySignal.type,
      confidence: primarySignal.confidence,
      reason: primarySignal.reason,
      greeks,
      allSignals: signals,
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Monitor Greeks for risk management
   */
  monitorGreeksForRisk(position) {
    const { symbol, greeks, entryGreeks, quantity, entryPrice } = position;

    const risks = [];

    // Delta hedging opportunity
    if (Math.abs(greeks.delta - entryGreeks.delta) > 0.2) {
      risks.push({
        risk: 'DELTA_DRIFT',
        severity: 'MEDIUM',
        action: 'REHEDGE',
        detail: `Delta changed from ${entryGreeks.delta.toFixed(3)} to ${greeks.delta.toFixed(3)}`
      });
    }

    // Gamma risk (non-linear movement)
    if (greeks.gamma > 0.02) {
      risks.push({
        risk: 'GAMMA_EXPLOSION',
        severity: 'HIGH',
        action: 'REDUCE_POSITION',
        detail: `Gamma at ${greeks.gamma.toFixed(4)}: expect sharp moves`
      });
    }

    // Vega risk (IV crash)
    if (greeks.vega > 20) {
      risks.push({
        risk: 'VEGA_EXPOSURE',
        severity: 'MEDIUM',
        action: 'IV_HEDGE',
        detail: `Vega at ${greeks.vega.toFixed(2)}: sensitive to IV changes`
      });
    }

    // Theta decay (time erosion)
    if (Math.abs(greeks.theta) > 5) {
      risks.push({
        risk: 'THETA_BLEED',
        severity: 'LOW',
        action: 'MONITOR',
        detail: `Daily theta: ${greeks.theta.toFixed(2)}`
      });
    }

    return risks.length > 0 
      ? { risks, timestamp: new Date().toISOString() }
      : { risks: [], status: 'SAFE', timestamp: new Date().toISOString() };
  }

  /**
   * Generate position-sizing recommendation
   */
  getPositionSizeRecommendation(capital, delta, gamma, theta, spot, strike) {
    const maxCapitalRisk = capital * 0.025; // 2.5% max risk per position

    // Adjust size based on Greeks
    let sizeMultiplier = 1.0;

    // Reduce size if gamma is high (less predictable)
    if (gamma > 0.015) {
      sizeMultiplier *= 0.7;
    }

    // Reduce size if theta decay is high (time sensitive)
    if (Math.abs(theta) > 2) {
      sizeMultiplier *= 0.8;
    }

    // Reduce size if strike is deep OTM (lower probability)
    const moneyness = Math.abs(spot - strike) / spot;
    if (moneyness > 0.05) {
      sizeMultiplier *= Math.pow(0.9, Math.floor(moneyness * 100));
    }

    const recommendedRisk = maxCapitalRisk * sizeMultiplier;
    return {
      maxRiskAmount: Math.round(recommendedRisk),
      sizeMultiplier: Math.round(sizeMultiplier * 1000) / 1000,
      rationale: `Based on gamma=${gamma.toFixed(4)}, theta=${theta.toFixed(2)}, moneyness=${(moneyness*100).toFixed(2)}%`
    };
  }
}

// Export modules
module.exports = {
  GreeksCalculator,
  SignalProcessor
};

// CLI Support for direct calls
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length >= 5) {
    const calc = new GreeksCalculator();
    const [S, K, E, V, type] = args;
    const res = calc.calculateGreeks(parseFloat(S), parseFloat(K), parseFloat(E), parseFloat(V), type || 'CALL');
    console.log(JSON.stringify(res));
  }
}
