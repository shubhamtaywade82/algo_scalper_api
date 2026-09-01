# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradeJournal do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:side) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:entry_price) }
    it { is_expected.to validate_numericality_of(:entry_price).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:entry_time) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:position_tracker) }
    it { is_expected.to belong_to(:instrument) }
  end

  describe '#winner? and #loser?' do
    it 'identifies a winner' do
      journal = build(:trade_journal, net_pnl: 100.0)
      expect(journal.winner?).to be true
      expect(journal.loser?).to be false
    end

    it 'identifies a loser' do
      journal = build(:trade_journal, net_pnl: -100.0)
      expect(journal.winner?).to be false
      expect(journal.loser?).to be true
    end
  end

  describe '#r_multiple' do
    it 'calculates r_multiple' do
      journal = build(:trade_journal, net_pnl: 200.0, max_adverse_excursion: 100.0)
      expect(journal.r_multiple).to eq 2.0
    end

    it 'returns nil if max_adverse_excursion is not present or not positive' do
      journal = build(:trade_journal, net_pnl: 200.0, max_adverse_excursion: nil)
      expect(journal.r_multiple).to be_nil
    end
  end
end
