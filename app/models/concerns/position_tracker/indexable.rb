# frozen_string_literal: true

class PositionTracker < ApplicationRecord
  module Indexable
    extend ActiveSupport::Concern

    included do
      after_commit :register_in_index, on: %i[create update], if: :index_registration_relevant?
      after_commit :unregister_from_index, on: :destroy
      after_update_commit :refresh_index_if_relevant
      after_create_commit :subscribe_to_feed, if: :feed_subscription_relevant?
    end

    def subscribe
      Positions::FeedSubscription.call(tracker: self)
    end

    def unsubscribe
      Positions::FeedSubscription.unsubscribe(tracker: self)
    end

    private

    def register_in_index
      Positions::IndexSync.new(tracker: self).register
    end

    def unregister_from_index
      Positions::IndexSync.new(tracker: self).unregister
      unsubscribe
    end

    def subscribe_to_feed
      subscribe
      register_in_index
    end

    def refresh_index_if_relevant
      Positions::IndexSync.new(tracker: self).refresh_if_relevant
    end

    def index_registration_relevant?
      active? && entry_price.present? && quantity.to_i.positive?
    end

    def feed_subscription_relevant?
      Positions::FeedSubscription.segment_key_for(tracker: self).present? && security_id.present?
    end
  end
end
