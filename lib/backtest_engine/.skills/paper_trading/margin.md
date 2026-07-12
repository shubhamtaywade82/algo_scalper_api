# Option Buying Margin Rules

Verify margin requirements before placing simulated orders.

## Verification Rules

1. **Available Cash Check**:
   - `Required Margin = OptionPremium * LotSize * Quantity + TransactionCosts`.
   - Reject the order immediately if `Required Margin > Available Cash`.

2. **Blocked Margin Tracking**:
   - Deduct the utilized margin from available cash upon order execution.
   - Release the blocked margin (and credit realized P&L) upon exit execution.
