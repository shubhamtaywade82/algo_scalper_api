# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::ExpiryRuleEngine do
  include ActiveSupport::Testing::TimeHelpers

  let(:symbol) { 'NIFTY' }
  let(:engine) { described_class.new(symbol: symbol) }
  let(:kolkata_tz) { 'Asia/Kolkata' }

  before do
    allow(Market::ExpiryChecker).to receive(:expiry_today?).with(symbol).and_return(true)
  end

  describe '#force_exit?' do
    context 'when it is not expiry day' do
      before do
        allow(Market::ExpiryChecker).to receive(:expiry_today?).with(symbol).and_return(false)
      end

      it 'returns false' do
        expect(engine.force_exit?).to be false
      end
    end

    context 'when it is expiry day' do
      it 'returns true after 15:10' do
        travel_to Time.find_zone(kolkata_tz).parse('2024-03-28 15:15:00') do
          expect(engine.force_exit?).to be true
        end
      end

      it 'returns false before 15:10' do
        travel_to Time.find_zone(kolkata_tz).parse('2024-03-28 15:05:00') do
          expect(engine.force_exit?).to be false
        end
      end
    end
  end

  describe '#tighten_trailing?' do
    context 'when it is not expiry day' do
      before do
        allow(Market::ExpiryChecker).to receive(:expiry_today?).with(symbol).and_return(false)
      end

      it 'returns false' do
        expect(engine.tighten_trailing?).to be false
      end
    end

    context 'when it is expiry day' do
      it 'returns true after 14:45' do
        travel_to Time.find_zone(kolkata_tz).parse('2024-03-28 14:50:00') do
          expect(engine.tighten_trailing?).to be true
        end
      end

      it 'returns false before 14:45' do
        travel_to Time.find_zone(kolkata_tz).parse('2024-03-28 14:40:00') do
          expect(engine.tighten_trailing?).to be false
        end
      end
    end
  end
end
