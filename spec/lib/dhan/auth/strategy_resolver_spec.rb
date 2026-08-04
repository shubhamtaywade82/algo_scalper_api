# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::Auth::StrategyResolver do
  describe ".resolve" do
    {
      "authority" => Dhan::Auth::Strategies::Authority,
      "totp" => Dhan::Auth::Strategies::Totp,
      "manual" => Dhan::Auth::Strategies::Manual,
      "renew" => Dhan::Auth::Strategies::Renew
    }.each do |mode, klass|
      context "when DHAN_AUTH_MODE=#{mode}" do
        before { stub_const("ENV", ENV.to_hash.merge("DHAN_AUTH_MODE" => mode)) }

        it "returns a #{klass.name} instance" do
          expect(described_class.resolve).to be_a(klass)
        end
      end
    end

    context "when DHAN_AUTH_MODE is not set" do
      before { stub_const("ENV", ENV.to_hash.except("DHAN_AUTH_MODE")) }

      it "defaults to Totp strategy" do
        expect(described_class.resolve).to be_a(Dhan::Auth::Strategies::Totp)
      end
    end

    context "when DHAN_AUTH_MODE has uppercase value" do
      before { stub_const("ENV", ENV.to_hash.merge("DHAN_AUTH_MODE" => "TOTP")) }

      it "resolves case-insensitively" do
        expect(described_class.resolve).to be_a(Dhan::Auth::Strategies::Totp)
      end
    end

    context "when DHAN_AUTH_MODE is an unknown value" do
      before { stub_const("ENV", ENV.to_hash.merge("DHAN_AUTH_MODE" => "oauth")) }

      it "raises ArgumentError with a helpful message" do
        expect { described_class.resolve }
          .to raise_error(ArgumentError, /Unknown DHAN_AUTH_MODE.*oauth/)
      end
    end
  end
end
