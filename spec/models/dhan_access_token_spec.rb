# == Schema Information
#
# Table name: dhan_access_tokens
#
#  id          :integer          not null, primary key
#  token       :string           not null
#  expiry_time :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_dhan_access_tokens_on_expiry_time  (expiry_time)
#

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DhanAccessToken do
  after { described_class.clear_active_cache }

  describe 'token encryption at rest' do
    it 'round-trips the plaintext value on read' do
      record = described_class.create!(token: 'plain-token-value', expiry_time: 1.hour.from_now)

      expect(record.reload.token).to eq('plain-token-value')
    end

    it 'stores ciphertext, not plaintext, in the database column' do
      record = described_class.create!(token: 'plain-token-value', expiry_time: 1.hour.from_now)

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT token FROM dhan_access_tokens WHERE id = #{record.id}"
      )
      expect(raw).not_to include('plain-token-value')
    end
  end

  describe '.active' do
    it 'returns the token with the latest expiry among unexpired rows' do
      described_class.create!(token: 'older', expiry_time: 1.hour.from_now)
      newest = described_class.create!(token: 'newest', expiry_time: 2.hours.from_now)

      expect(described_class.active.token).to eq(newest.token)
    end

    it 'ignores expired rows' do
      described_class.create!(token: 'expired', expiry_time: 1.hour.ago)

      expect(described_class.active).to be_nil
    end

    # Test env's Rails.cache is a NullStore (writes "succeed" but nothing is ever readable),
    # so these two specs swap in a real store to actually exercise the cache round-trip.
    context 'with a real cache store' do
      let(:real_cache) { ActiveSupport::Cache::MemoryStore.new }

      before { allow(Rails).to receive(:cache).and_return(real_cache) }

      it 'caches only the row id, not the decrypted token, to avoid leaking plaintext into Rails.cache' do
        record = described_class.create!(token: 'plain-token-value', expiry_time: 1.hour.from_now)

        described_class.active

        cached = real_cache.read(described_class::CACHE_KEY)
        expect(cached).to eq(record.id)
        expect(cached.to_s).not_to include('plain-token-value')
      end

      it 'still returns the correctly decrypted token when served from cache' do
        described_class.create!(token: 'plain-token-value', expiry_time: 1.hour.from_now)

        described_class.active # primes the id cache
        cached_result = described_class.active # reads id from cache, record fresh from DB

        expect(cached_result.token).to eq('plain-token-value')
      end
    end
  end
end
