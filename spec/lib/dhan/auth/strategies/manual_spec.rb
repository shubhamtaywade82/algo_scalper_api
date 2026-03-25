# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::Auth::Strategies::Manual do
  include ActiveSupport::Testing::TimeHelpers

  subject(:strategy) { described_class.new }

  describe "#call" do
    context "when DHAN_ACCESS_TOKEN is set" do
      before { stub_const("ENV", ENV.to_hash.merge("DHAN_ACCESS_TOKEN" => "manual_tok_abc")) }

      it "returns the token from ENV" do
        result = strategy.call
        expect(result[:access_token]).to eq("manual_tok_abc")
      end

      it "sets expiry to ~24 hours from now" do
        freeze_time do
          result = strategy.call
          expect(result[:expiry_time]).to be_within(1.second).of(24.hours.from_now)
        end
      end
    end

    context "when DHAN_ACCESS_TOKEN is blank" do
      before { stub_const("ENV", ENV.to_hash.merge("DHAN_ACCESS_TOKEN" => "")) }

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/Manual token missing/)
      end
    end

    context "when DHAN_ACCESS_TOKEN is absent" do
      before { stub_const("ENV", ENV.to_hash.except("DHAN_ACCESS_TOKEN")) }

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/Manual token missing/)
      end
    end
  end
end
