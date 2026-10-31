# frozen_string_literal: true

# TDD §16 A1.9 — LotReducer: deterministic FIFO order (acquired_on, id),
# partial consumption, T+1 guard (t1 quantity not sellable), typed
# InsufficientQuantity error, available_quantity decrement.
require "rails_helper"

RSpec.describe Investing::Portfolios::LotReducer do
  subject(:reducer) { described_class.new }

  let(:holding) { create(:investment_holding, quantity: 100, available_quantity: 100) }
  let(:trade_date) { Date.new(2026, 10, 31) }

  describe "#consume_fifo!" do
    context "deterministic FIFO ordering (acquired_on, id)" do
      it "consumes the OLDEST lot first, ties broken by id" do
        newest = create(:investment_lot, investment_holding: holding,
                                         acquired_on: 10.days.ago, quantity: 40, remaining_quantity: 40)
        oldest = create(:investment_lot, :older, investment_holding: holding,
                                                 quantity: 40, remaining_quantity: 40)
        middle = create(:investment_lot, investment_holding: holding,
                                         acquired_on: 20.days.ago, quantity: 40, remaining_quantity: 40)

        consumptions = reducer.consume_fifo!(holding, quantity: 50, trade_date: trade_date)

        # oldest fully consumed (40) + middle partially (10) = 2 consumption rows;
        # newest is never touched.
        expect(consumptions.length).to eq(2)
        expect(oldest.reload.remaining_quantity).to eq(0)
        expect(middle.reload.remaining_quantity).to eq(30)
        expect(newest.reload.remaining_quantity).to eq(40)
        expect(consumptions[0].lot.id).to eq(oldest.id)
        expect(consumptions[0].quantity_taken).to eq(40)
        expect(consumptions[1].lot.id).to eq(middle.id)
        expect(consumptions[1].quantity_taken).to eq(10)
      end

      it "breaks ties on acquired_on by id ASC (never DB default order)" do
        a = nil
        b = nil
        ActiveRecord::Base.transaction do
          a = create(:investment_lot, investment_holding: holding, acquired_on: 15.days.ago,
                                      quantity: 10, remaining_quantity: 10)
          b = create(:investment_lot, investment_holding: holding, acquired_on: 15.days.ago,
                                      quantity: 10, remaining_quantity: 10)
        end
        consumptions = reducer.consume_fifo!(holding, quantity: 10, trade_date: trade_date)
        expect(consumptions.map { |c| c.lot.id }).to eq([a.id, b.id].minmax.take(1))
        expect(b.reload.remaining_quantity).to eq(10)
        expect(a.reload.remaining_quantity).to eq(0)
      end
    end

    context "partial consumption" do
      it "partially consumes a single lot when quantity < lot remaining" do
        lot = create(:investment_lot, investment_holding: holding,
                                      quantity: 100, remaining_quantity: 100)
        consumptions = reducer.consume_fifo!(holding, quantity: 30, trade_date: trade_date)

        expect(consumptions.size).to eq(1)
        expect(consumptions.first.quantity_taken).to eq(30)
        expect(lot.reload.remaining_quantity).to eq(70)
        expect(holding.reload.available_quantity).to eq(70)
        # a sell removes shares from the book: quantity drops too
        expect(holding.reload.quantity).to eq(70)
      end

      it "skips fully-consumed lots in the FIFO scan" do
        exhausted = create(:investment_lot, :partially_consumed, investment_holding: holding,
                                                                 acquired_on: 60.days.ago,
                                                                 remaining_quantity: 0)
        create(:investment_lot, investment_holding: holding, acquired_on: 10.days.ago,
                                quantity: 50, remaining_quantity: 50)
        consumptions = reducer.consume_fifo!(holding, quantity: 20, trade_date: trade_date)

        expect(exhausted.reload.remaining_quantity).to eq(0)
        expect(consumptions.map { |c| c.lot.id }).not_to include(exhausted.id)
      end
    end

    context "T+1 guard (A1.9)" do
      it "raises InsufficientQuantity when selling more than available (t1 excluded)" do
        holding.update!(quantity: 110, available_quantity: 100, t1_quantity: 10)

        expect {
          reducer.consume_fifo!(holding, quantity: 105, trade_date: trade_date)
        }.to raise_error(Investing::InsufficientQuantity, /t1_quantity .* is not yet sellable/)
      end

      it "allows selling exactly the available quantity" do
        holding.update!(quantity: 110, available_quantity: 100, t1_quantity: 10)
        create(:investment_lot, investment_holding: holding, quantity: 110,
                                remaining_quantity: 110, acquired_on: 5.days.ago)
        consumptions = reducer.consume_fifo!(holding, quantity: 100, trade_date: trade_date)
        expect(consumptions.first.quantity_taken).to eq(100)
        # 100 of 110 sold: available 0, t1 10 still settling, quantity 10
        expect(holding.reload.available_quantity).to eq(0)
        expect(holding.reload.quantity).to eq(10)
        expect(holding.reload.t1_quantity).to eq(10)
      end
    end

    context "typed errors" do
      it "raises ValidationError for zero or negative quantity" do
        expect { reducer.consume_fifo!(holding, quantity: 0, trade_date: trade_date) }
          .to raise_error(Investing::ValidationError, /must be positive/)
        expect { reducer.consume_fifo!(holding, quantity: -5, trade_date: trade_date) }
          .to raise_error(Investing::ValidationError, /must be positive/)
      end

      it "never raises bare StandardError for business rejections" do
        begin
          reducer.consume_fifo!(holding, quantity: 1_000, trade_date: trade_date)
        rescue StandardError => e
          expect(e).to be_a(Investing::InsufficientQuantity)
        end
      end
    end

    context "invariant enforcement" do
      it "raises InsufficientQuantity when lots cannot cover the request (data drift)" do
        # holding claims 100 available but lots only hold 30 — the belt-and-braces
        # check must fire rather than silently under-consume.
        create(:investment_lot, investment_holding: holding, quantity: 30,
                                remaining_quantity: 30, acquired_on: 5.days.ago)
        expect {
          reducer.consume_fifo!(holding, quantity: 100, trade_date: trade_date)
        }.to raise_error(Investing::InsufficientQuantity, /lot inconsistency/)
      end
    end
  end
end
