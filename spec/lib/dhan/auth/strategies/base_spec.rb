# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::Auth::Strategies::Base do
  subject(:strategy) { described_class.new }

  describe "#call" do
    it "raises NotImplementedError" do
      expect { strategy.call }.to raise_error(NotImplementedError)
    end
  end

  describe "#normalize_response (via subclass)" do
    let(:concrete) do
      Class.new(described_class) do
        def call
          normalize_response(token: "tok123", expiry: Time.parse("2026-01-01 12:00:00 UTC"))
        end
      end.new
    end

    it "returns a hash with :access_token and :expiry_time" do
      result = concrete.call
      expect(result[:access_token]).to eq("tok123")
      expect(result[:expiry_time]).to eq(Time.parse("2026-01-01 12:00:00 UTC"))
    end
  end
end
