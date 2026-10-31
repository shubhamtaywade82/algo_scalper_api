# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Config do
  describe "configuration isolation from the Trading domain (A-CONF-01)" do
    it "does not expose any trading paper/live switch" do
      expect(described_class).not_to respond_to(:paper_trading_enabled)
      expect(described_class).not_to respond_to(:paper_trading_enabled?)
      expect(described_class).not_to respond_to(:algo_settings)
    end

    it "adds no investing keys to the trading settings schema" do
      expect(AlgoSetting::SCHEMA.keys.none? { |key| key.start_with?("investing") }).to be(true)
    end

    it "keeps the trading switch readable from its own store" do
      expect(AlgoSetting::SCHEMA).to include("paper_trading_enabled")
    end
  end

  describe "#enabled?" do
    it "is enabled in the test environment" do
      expect(described_class).to be_enabled
    end
  end

  describe "execution mode (A-CONF-02)" do
    # The test environment configures paper mode; the confirmation guard is
    # exercised by temporarily flipping the loaded mode to "live".
    def with_configured_mode(mode)
      original = Rails.application.config.x.investing
      Rails.application.config.x.investing =
        original.merge(execution: original[:execution].merge(mode: mode))
      yield
    ensure
      Rails.application.config.x.investing = original
    end

    it "stays paper while the confirmation env is absent" do
      with_configured_mode("live") do
        stub_env(described_class::LIVE_CONFIRMATION_ENV, nil) do
          expect(described_class).to be_paper
          expect(described_class.execution_mode).to eq("paper")
        end
      end
    end

    it "stays paper with a wrong confirmation phrase" do
      with_configured_mode("live") do
        stub_env(described_class::LIVE_CONFIRMATION_ENV, "yes") do
          expect(described_class).to be_paper
        end
      end
    end

    it "reports live only with the exact phrase" do
      with_configured_mode("live") do
        stub_env(described_class::LIVE_CONFIRMATION_ENV, described_class::LIVE_CONFIRMATION_PHRASE) do
          expect(described_class).to be_live
          expect(described_class.execution_mode).to eq("live")
        end
      end
    end
  end

  describe "approval and safety switches" do
    it "requires approval and forbids margin/derivatives by default" do
      expect(described_class.require_approval).to be(true)
      expect(described_class.automatic_execution?).to be(false)
      expect(described_class.allow_margin?).to be(false)
      expect(described_class.allow_derivatives?).to be(false)
    end
  end

  describe ".validate! (A-CONF-03)" do
    it "accepts paper mode without approval" do
      expect do
        described_class.validate!({ execution: { mode: "paper", require_approval: false } })
      end.not_to raise_error
    end

    it "accepts live mode with approval required" do
      expect do
        described_class.validate!({ execution: { mode: "live", require_approval: true } })
      end.not_to raise_error
    end

    it "rejects live mode with approval disabled — fail closed at boot" do
      expect do
        described_class.validate!({ execution: { mode: "live", require_approval: false } })
      end.to raise_error(Investing::Config::ConfigurationError,
                         /require_approval cannot be false while mode is live/)
    end

    it "rejects an unknown mode" do
      expect do
        described_class.validate!({ execution: { mode: "turbo" } })
      end.to raise_error(Investing::Config::ConfigurationError, /must be one of/)
    end
  end

  describe ".mandates" do
    it "exposes the balanced_v1 seed mandate" do
      expect(described_class.mandates).to include(:balanced_v1)
    end
  end

  private

  # Minimal ENV stub (avoids adding a gem for one spec file).
  def stub_env(key, value)
    original = ENV.fetch(key, nil)
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end
end
