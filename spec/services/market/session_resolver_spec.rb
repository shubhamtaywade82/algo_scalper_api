# frozen_string_literal: true

require "rails_helper"

RSpec.describe Market::SessionResolver do
  describe ".current" do
    it "returns :opening between 09:15 and 10:30 IST" do
      travel_to Time.zone.parse("2025-03-18 09:30:00 +0530") do
        expect(described_class.current).to eq(:opening)
      end
    end

    it "returns :gamma between 14:00 and 15:15 IST" do
      travel_to Time.zone.parse("2025-03-18 14:30:00 +0530") do
        expect(described_class.current).to eq(:gamma)
      end
    end

    it "returns :midday between 10:30 and 14:00 IST" do
      travel_to Time.zone.parse("2025-03-18 12:00:00 +0530") do
        expect(described_class.current).to eq(:midday)
      end
    end
  end
end
