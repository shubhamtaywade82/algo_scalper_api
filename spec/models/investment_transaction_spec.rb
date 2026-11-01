# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentTransaction do
  subject(:txn) { build(:investment_transaction) }

  it { is_expected.to belong_to(:investment_portfolio) }

  it "accepts every documented txn_type" do
    described_class::TXN_TYPES.each do |type|
      expect(build(:investment_transaction, txn_type: type)).to be_valid
    end
  end

  it "rejects an unknown txn_type" do
    txn.txn_type = "gamble"
    expect(txn).not_to be_valid
  end

  it "accepts signed quantity_delta (+buy / -sell) and 0 for cash rows" do
    expect(build(:investment_transaction, quantity_delta: -25)).to be_valid
    expect(build(:investment_transaction, quantity_delta: 25)).to be_valid
    expect(build(:investment_transaction, quantity_delta: 0)).to be_valid
  end
end
