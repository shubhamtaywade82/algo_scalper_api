# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WatchlistItem do
  describe 'EPIC B — B1: Maintain Watchlist Items' do
    describe 'associations' do
      it 'belongs to watchable (polymorphic)' do
        instrument = create(:instrument, :nifty_index)
        watchlist_item = create(:watchlist_item, :for_instrument, watchable: instrument)

        expect(watchlist_item.watchable).to eq(instrument)
        expect(watchlist_item.watchable_type).to eq('Instrument')
      end

      it 'can belong to an Instrument' do
        instrument = create(:instrument, :nifty_index)
        watchlist_item = create(:watchlist_item, watchable: instrument)

        expect(watchlist_item.watchable).to eq(instrument)
        expect(watchlist_item.instrument).to eq(instrument)
      end

      it 'can belong to a Derivative' do
        instrument = create(:instrument, :nifty_index)
        derivative = create(:derivative, instrument: instrument, security_id: '50074')
        watchlist_item = create(:watchlist_item, watchable: derivative)

        expect(watchlist_item.watchable).to eq(derivative)
        expect(watchlist_item.derivative).to eq(derivative)
      end

      it 'has optional watchable association' do
        watchlist_item = build(:watchlist_item, watchable: nil)
        expect(watchlist_item).to be_valid
      end
    end

    describe 'validations' do
      it 'requires segment' do
        watchlist_item = build(:watchlist_item, segment: nil)
        expect(watchlist_item).not_to be_valid
        expect(watchlist_item.errors[:segment]).to include("can't be blank")
      end

      it 'requires security_id' do
        watchlist_item = build(:watchlist_item, security_id: nil)
        expect(watchlist_item).not_to be_valid
        expect(watchlist_item.errors[:security_id]).to include("can't be blank")
      end

      it 'validates segment inclusion in allowed segments' do
        watchlist_item = build(:watchlist_item, segment: 'INVALID_SEGMENT')
        expect(watchlist_item).not_to be_valid
        expect(watchlist_item.errors[:segment]).to include('is not included in the list')
      end

      it 'allows valid segments' do
        WatchlistItem::ALLOWED_SEGMENTS.each do |segment|
          watchlist_item = build(:watchlist_item, segment: segment)
          expect(watchlist_item).to be_valid, "Segment #{segment} should be valid"
        end
      end

      it 'enforces uniqueness of security_id scoped to segment' do
        create(:watchlist_item, segment: 'IDX_I', security_id: '13')
        duplicate = build(:watchlist_item, segment: 'IDX_I', security_id: '13')

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:security_id]).to include('has already been taken')
      end

      it 'allows same security_id in different segments' do
        create(:watchlist_item, segment: 'IDX_I', security_id: '13')
        duplicate = build(:watchlist_item, segment: 'NSE_FNO', security_id: '13')

        expect(duplicate).to be_valid
      end

      it 'has active defaulting to true' do
        watchlist_item = WatchlistItem.new(segment: 'IDX_I', security_id: '99')
        watchlist_item.valid? # Trigger validation to set defaults
        expect(watchlist_item.active).to be true
      end
    end

    describe 'enum validations' do
      it 'accepts valid kind values' do
        %i[index_value equity derivative currency commodity].each do |kind|
          watchlist_item = build(:watchlist_item, kind: kind)
          expect(watchlist_item).to be_valid, "Kind #{kind} should be valid"
        end
      end

      it 'rejects invalid kind values' do
        watchlist_item = build(:watchlist_item)
        watchlist_item.kind = 999 # Invalid enum value

        expect(watchlist_item).not_to be_valid
      end
    end

    describe 'scopes' do
      let!(:active_item) { create(:watchlist_item, :active, segment: 'IDX_I', security_id: '13') }
      let!(:inactive_item) { create(:watchlist_item, :inactive, segment: 'IDX_I', security_id: '25') }
      let!(:another_active_item) { create(:watchlist_item, :active, segment: 'NSE_FNO', security_id: '50074') }

      describe '.active' do
        it 'returns only active watchlist items' do
          active_items = described_class.active

          expect(active_items).to include(active_item)
          expect(active_items).to include(another_active_item)
          expect(active_items).not_to include(inactive_item)
        end

        it 'can be chained with other scopes' do
          result = described_class.active.where(segment: 'IDX_I')
          expect(result).to contain_exactly(active_item)
        end
      end

      describe '.by_segment' do
        it 'filters by segment' do
          result = described_class.by_segment('IDX_I')
          expect(result).to contain_exactly(active_item, inactive_item)
        end
      end

      describe '.for' do
        it 'filters by segment and security_id' do
          result = described_class.for('IDX_I', '13')
          expect(result).to contain_exactly(active_item)
        end
      end
    end

    describe 'helper methods' do
      describe '#instrument' do
        it 'returns watchable when watchable_type is Instrument' do
          instrument = create(:instrument, :nifty_index)
          watchlist_item = create(:watchlist_item, watchable: instrument)

          expect(watchlist_item.instrument).to eq(instrument)
        end

        it 'returns nil when watchable_type is not Instrument' do
          instrument = create(:instrument, :nifty_index)
          derivative = create(:derivative, instrument: instrument, security_id: '50074')
          watchlist_item = create(:watchlist_item, watchable: derivative)

          expect(watchlist_item.instrument).to be_nil
        end

        it 'returns nil when watchable is nil' do
          watchlist_item = create(:watchlist_item, watchable: nil)

          expect(watchlist_item.instrument).to be_nil
        end
      end

      describe '#derivative' do
        it 'returns watchable when watchable_type is Derivative' do
          instrument = create(:instrument, :nifty_index)
          derivative = create(:derivative, instrument: instrument, security_id: '50074')
          watchlist_item = create(:watchlist_item, watchable: derivative)

          expect(watchlist_item.derivative).to eq(derivative)
        end

        it 'returns nil when watchable_type is not Derivative' do
          instrument = create(:instrument, :nifty_index)
          watchlist_item = create(:watchlist_item, watchable: instrument)

          expect(watchlist_item.derivative).to be_nil
        end

        it 'returns nil when watchable is nil' do
          watchlist_item = create(:watchlist_item, watchable: nil)

          expect(watchlist_item.derivative).to be_nil
        end
      end
    end

    describe 'AC 1: WatchlistItem Model structure' do
      it 'has all required fields' do
        watchlist_item = create(:watchlist_item)

        expect(watchlist_item).to respond_to(:segment)
        expect(watchlist_item).to respond_to(:security_id)
        expect(watchlist_item).to respond_to(:active)
        expect(watchlist_item).to respond_to(:kind)
        expect(watchlist_item).to respond_to(:label)
        expect(watchlist_item).to respond_to(:watchable_type)
        expect(watchlist_item).to respond_to(:watchable_id)
      end

      it 'has polymorphic watchable association' do
        watchlist_item = build(:watchlist_item)
        expect(watchlist_item).to respond_to(:watchable)
        expect(watchlist_item).to respond_to(:instrument)
        expect(watchlist_item).to respond_to(:derivative)
      end

      it 'enforces unique constraint on [segment, security_id]' do
        create(:watchlist_item, segment: 'IDX_I', security_id: '13')

        expect do
          create(:watchlist_item, segment: 'IDX_I', security_id: '13')
        end.to raise_error(ActiveRecord::RecordInvalid, /Security has already been taken/)
      end
    end

    describe 'AC 3: Query/Subscription' do
      let!(:active_nifty) { create(:watchlist_item, :nifty_index, :active) }
      let!(:active_banknifty) { create(:watchlist_item, :banknifty_index, :active) }
      let!(:inactive_sensex) { create(:watchlist_item, :sensex_index, :inactive) }

      it 'returns only active items via active scope' do
        active_items = described_class.active

        expect(active_items).to include(active_nifty)
        expect(active_items).to include(active_banknifty)
        expect(active_items).not_to include(inactive_sensex)
      end

      it 'can be formatted for WebSocket subscription' do
        watchlist_data = described_class.active.order(:segment, :security_id)
          .pluck(:segment, :security_id)
          .map { |seg, sid| { segment: seg, security_id: sid } }

        expect(watchlist_data).to be_an(Array)
        expect(watchlist_data.first).to have_key(:segment)
        expect(watchlist_data.first).to have_key(:security_id)
        expect(watchlist_data.length).to eq(2) # Only active items
      end

      it 'excludes inactive items from subscription' do
        subscription_list = described_class.active.pluck(:segment, :security_id)

        expect(subscription_list).not_to include([inactive_sensex.segment, inactive_sensex.security_id])
      end
    end

    describe 'seeding requirements (AC 2)' do
      it 'supports creating NIFTY watchlist item' do
        instrument = create(:instrument, :nifty_index, security_id: '13', segment: 'I', exchange: 'NSE')
        watchlist_item = create(:watchlist_item, :nifty_index, watchable: instrument)

        expect(watchlist_item.segment).to eq('IDX_I')
        expect(watchlist_item.security_id).to eq('13')
        expect(watchlist_item.active).to be true
        expect(watchlist_item.kind).to eq('index_value')
        expect(watchlist_item.watchable).to eq(instrument)
      end

      it 'supports creating BANKNIFTY watchlist item' do
        instrument = create(:instrument, symbol_name: 'BANKNIFTY', security_id: '25', segment: 'I', exchange: 'NSE')
        watchlist_item = create(:watchlist_item, :banknifty_index, watchable: instrument)

        expect(watchlist_item.segment).to eq('IDX_I')
        expect(watchlist_item.security_id).to eq('25')
        expect(watchlist_item.active).to be true
        expect(watchlist_item.kind).to eq('index_value')
      end

      it 'supports creating SENSEX watchlist item' do
        instrument = create(:instrument, symbol_name: 'SENSEX', security_id: '51', segment: 'I', exchange: 'BSE')
        watchlist_item = create(:watchlist_item, :sensex_index, watchable: instrument)

        expect(watchlist_item.security_id).to eq('51')
        expect(watchlist_item.active).to be true
        expect(watchlist_item.kind).to eq('index_value')
      end

      it 'allows linking to Instrument via polymorphic watchable' do
        instrument = create(:instrument, :nifty_index)
        watchlist_item = create(:watchlist_item, :nifty_index, watchable: instrument)

        expect(watchlist_item.watchable_type).to eq('Instrument')
        expect(watchlist_item.watchable_id).to eq(instrument.id)
        expect(watchlist_item.instrument).to eq(instrument)
      end
    end
  end
end

