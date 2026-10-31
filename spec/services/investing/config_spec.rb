# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Config do
  after do
    described_class.reset!
    # Restore the app-wide memoized instance: other spec files (Creator,
    # services) depend on Investing::Config.fetch behaving as it does after
    # the real initializer ran — a bare reset! leaves them with a boot-bug
    # state (cross-file pollution).
    described_class.load!
  rescue described_class::Error
    nil
  end

  # Build a minimal valid config as a Ruby hash and dump to YAML — avoids
  # heredoc indentation pitfalls. Sleeve weights sum to exactly 100.
  def config_hash(sleeves: default_sleeves, mode: "paper", constraints: default_constraints)
    {
      "default" => {
        "execution" => {
          "mode" => mode,
          "require_manual_approval" => true,
          "max_order_value_inr" => 500_000,
          "max_orders_per_day" => 12
        },
        "mandates" => {
          "balanced_v1" => {
            "description" => "test",
            "rebalance_band_pct" => [50, 60],
            "sleeves" => sleeves,
            "constraints" => constraints,
            "rebalancing" => {
              "review_cadence" => "quarterly",
              "drift_threshold_pct" => 5,
              "equity_band_pct" => [50, 60]
            },
            "deployment" => {
              "equity_tranches" => 3,
              "tranche_spacing_weeks" => 4,
              "midcap_stp_months" => 6
            }
          }
        }
      }
    }
  end

  def default_sleeves
    [
      { "key" => "large_cap_core", "name" => "Large-Cap Core",
        "asset_class" => "equity", "target_weight_pct" => 60 },
      { "key" => "govt_aaa_bonds", "name" => "Bonds",
        "asset_class" => "debt", "target_weight_pct" => 32 },
      { "key" => "cash", "name" => "Cash",
        "asset_class" => "cash", "target_weight_pct" => 8 }
    ]
  end

  def default_constraints
    { "max_single_stock_pct" => 2.5, "max_sector_pct" => 12,
      "max_illiquid_pct" => 25, "min_sleeve_holdings" => 3 }
  end

  def write_config(**overrides)
    file = Tempfile.new(%w[investing .yml])
    file.write(YAML.dump(config_hash(**overrides)))
    file.flush
    file
  end

  def with_env(name, value)
    old = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    ENV[name] = old
  end

  describe "the repo's real config/investing.yml" do
    it "loads and validates the balanced_v1 mandate" do
      config = described_class.load!
      expect(config.execution["mode"]).to eq("paper")
      expect(config.mandates.keys).to include("balanced_v1")
      sleeves = config.sleeves_for("balanced_v1")
      expect(sleeves.size).to eq(10)
      expect(sleeves.sum { |s| s["target_weight_pct"] }).to eq(100)
    end

    it "exposes band/drift accessors" do
      config = described_class.load!
      expect(config.equity_band_for("balanced_v1")).to eq([BigDecimal("50"), BigDecimal("60")])
      expect(config.drift_threshold_for("balanced_v1")).to eq(5)
    end

    it "is memoized and fetchable" do
      config = described_class.load!
      expect(described_class.fetch).to equal(config)
    end

    it "raises on unknown mandate" do
      described_class.load!
      expect { described_class.fetch.mandate("nope") }
        .to raise_error(described_class::Error, /unknown investing mandate: nope/)
    end
  end

  describe "sleeve weight validation (TDD §5.2)" do
    it "rejects weights summing to 99.5" do
      sleeves = default_sleeves.map do |s|
        s["key"] == "cash" ? s.merge("target_weight_pct" => 7.5) : s
      end
      file = write_config(sleeves: sleeves)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /sum to exactly 100 \(got 99\.5\)/)
    end

    it "rejects weights summing to 100.5" do
      sleeves = default_sleeves.map do |s|
        s["key"] == "cash" ? s.merge("target_weight_pct" => 8.5) : s
      end
      file = write_config(sleeves: sleeves)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /sum to exactly 100 \(got 100\.5\)/)
    end

    it "rejects duplicate sleeve keys" do
      sleeves = default_sleeves.map do |s|
        s["key"] == "cash" ? s.merge("target_weight_pct" => 7) : s
      end
      sleeves << { "key" => "cash", "name" => "Cash dup",
                   "asset_class" => "cash", "target_weight_pct" => 1 }
      file = write_config(sleeves: sleeves)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /duplicate sleeve keys/)
    end

    it "rejects a non-positive weight" do
      sleeves = default_sleeves.map do |s|
        case s["key"]
        when "large_cap_core" then s.merge("target_weight_pct" => 0)
        when "govt_aaa_bonds" then s.merge("target_weight_pct" => 92)
        else s
        end
      end
      file = write_config(sleeves: sleeves)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /weight must be in \(0,100\]/)
    end

    it "rejects an unknown asset class" do
      sleeves = default_sleeves.map do |s|
        s["key"] == "cash" ? s.merge("asset_class" => "crypto") : s
      end
      file = write_config(sleeves: sleeves)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /asset_class must be one of/)
    end

    it "rejects an equity target outside the band" do
      sleeves = default_sleeves.map do |s|
        case s["key"]
        when "large_cap_core" then s.merge("target_weight_pct" => 62)
        when "govt_aaa_bonds" then s.merge("target_weight_pct" => 30)
        else s
        end
      end
      file = write_config(sleeves: sleeves)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /equity target 62\.0 outside band/)
    end

    it "rejects max_single_stock_pct above max_sector_pct" do
      constraints = default_constraints.merge("max_single_stock_pct" => 15)
      file = write_config(constraints: constraints)
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /max_single_stock_pct must be <= max_sector_pct/)
    end

    it "rejects an empty sleeve list" do
      file = write_config(sleeves: [])
      expect { described_class.load!(path: file.path) }
        .to raise_error(described_class::Error, /sleeves must be a non-empty list/)
    end
  end

  describe "execution-mode safety rails (TDD §19.2)" do
    it "refuses live mode without INVESTING_LIVE_CONFIRMED=yes" do
      file = write_config(mode: "live")
      with_env("INVESTING_LIVE_CONFIRMED", nil) do
        expect { described_class.load!(path: file.path) }
          .to raise_error(described_class::Error, /INVESTING_LIVE_CONFIRMED=yes/)
      end
    end

    it "allows live mode with the confirmation env" do
      file = write_config(mode: "live")
      with_env("INVESTING_LIVE_CONFIRMED", "yes") do
        expect { described_class.load!(path: file.path) }.not_to raise_error
      end
    end
  end

  describe "fetch before load" do
    it "raises a helpful error" do
      described_class.reset!
      expect { described_class.fetch }
        .to raise_error(described_class::Error, /not loaded/)
    end
  end
end
