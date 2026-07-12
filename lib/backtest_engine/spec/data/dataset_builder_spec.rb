require "spec_helper"

RSpec.describe BacktestEngine::Data::DatasetBuilder do
  describe "symbol resolution" do
    let(:index_candles) { [] }
    let(:option_data) { {} }

    before do
      allow(BacktestEngine::Data::IndexLoader).to receive(:fetch).and_return(index_candles)
      allow(BacktestEngine::Data::OptionsLoader).to receive(:fetch).and_return(option_data)
    end

    context "when symbol is given" do
      it "uses InstrumentMetadata.security_id for that symbol" do
        described_class.new(
          interval: 1,
          from: "2025-01-01 09:15:00",
          to: "2025-01-01 15:30:00",
          expiry_code: 1,
          symbol: "BANKNIFTY"
        ).build

        expect(BacktestEngine::Data::IndexLoader).to have_received(:fetch).with(
          hash_including(security_id: "25")
        )
        expect(BacktestEngine::Data::OptionsLoader).to have_received(:fetch).with(
          hash_including(security_id: "25")
        )
      end
    end

    context "when security_id is given and symbol is nil" do
      it "uses the given security_id" do
        described_class.new(
          interval: 1,
          from: "2025-01-01 09:15:00",
          to: "2025-01-01 15:30:00",
          expiry_code: 1,
          security_id: "99"
        ).build

        expect(BacktestEngine::Data::IndexLoader).to have_received(:fetch).with(
          hash_including(security_id: "99")
        )
      end
    end

    context "when neither symbol nor security_id is given" do
      it "defaults to NIFTY security_id" do
        described_class.new(
          interval: 1,
          from: "2025-01-01 09:15:00",
          to: "2025-01-01 15:30:00",
          expiry_code: 1
        ).build

        expect(BacktestEngine::Data::IndexLoader).to have_received(:fetch).with(
          hash_including(security_id: BacktestEngine::Data::IndexLoader::NIFTY_SECURITY_ID)
        )
      end
    end
  end
end
