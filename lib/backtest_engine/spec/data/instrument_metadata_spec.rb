require "spec_helper"

RSpec.describe BacktestEngine::Data::InstrumentMetadata do
  describe ".supported_symbols" do
    it "returns NIFTY, BANKNIFTY, SENSEX" do
      expect(described_class.supported_symbols).to contain_exactly("NIFTY", "BANKNIFTY", "SENSEX")
    end
  end

  describe ".security_id" do
    it "returns DhanHQ security ID for known symbol" do
      expect(described_class.security_id("NIFTY")).to eq("13")
      expect(described_class.security_id("BANKNIFTY")).to eq("25")
      expect(described_class.security_id("SENSEX")).to eq("1")
    end

    it "normalizes symbol to uppercase" do
      expect(described_class.security_id("nifty")).to eq("13")
      expect(described_class.security_id(:banknifty)).to eq("25")
    end

    context "when symbol is unknown" do
      it "raises ArgumentError with supported list" do
        expect { described_class.security_id("UNKNOWN") }.to raise_error(ArgumentError, /Unknown symbol.*NIFTY.*BANKNIFTY.*SENSEX/)
      end
    end
  end

  describe ".lot_size" do
    it "returns lot size for known symbol" do
      expect(described_class.lot_size("NIFTY")).to eq(50)
      expect(described_class.lot_size("BANKNIFTY")).to eq(15)
      expect(described_class.lot_size("SENSEX")).to eq(10)
    end

    it "normalizes symbol to uppercase" do
      expect(described_class.lot_size("sensex")).to eq(10)
    end

    context "when symbol is unknown" do
      it "raises ArgumentError with supported list" do
        expect { described_class.lot_size("MIDCPNIFTY") }.to raise_error(ArgumentError, /Unknown symbol.*NIFTY.*BANKNIFTY.*SENSEX/)
      end
    end
  end
end
