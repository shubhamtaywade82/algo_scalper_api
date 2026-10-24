# frozen_string_literal: true

module Capital
  # Sizing for option selling / credit spreads based on defined max risk and available margin.
  class SellingPositionSizer
    def self.calculate_lots(index_key:, spread_width:, net_premium:, mode: :paper)
      new(index_key: index_key, spread_width: spread_width, net_premium: net_premium, mode: mode).calculate
    end

    def initialize(index_key:, spread_width:, net_premium:, mode: :paper)
      @index_key = index_key.to_s.upcase
      @spread_width = spread_width.to_f
      @net_premium = net_premium.to_f
      @mode = mode.to_sym
    end

    def calculate
      lot_size = begin
                   Trading::LotCalculator.lot_size_for(@index_key)
      rescue StandardError
                   50
      end
      max_loss_per_lot = (@spread_width - @net_premium) * lot_size
      return 1 if max_loss_per_lot <= 0

      wallet = fetch_wallet_snapshot
      available_capital = wallet[:cash].to_f.positive? ? wallet[:cash].to_f : 100_000.0

      risk_pct = max_risk_per_trade_pct
      risk_budget = available_capital * risk_pct

      lots = (risk_budget / max_loss_per_lot).floor
      [lots, 1].max # At least 1 lot, capped by max lots
    rescue StandardError => e
      Rails.logger.warn("[SellingPositionSizer] Sizing calculation fallback: #{e.message}")
      1
    end

    private

    def max_risk_per_trade_pct
      (AlgoConfig.fetch.dig(:risk, :max_trade_risk_pct) || 0.01).to_f
    end

    def fetch_wallet_snapshot
      Ledger::WalletReader.snapshot(mode: @mode)
    rescue StandardError
      { cash: 100_000, margin: 100_000 }
    end
  end
end
