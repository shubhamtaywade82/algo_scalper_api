# frozen_string_literal: true

require 'securerandom'

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :connection_id

    def connect
      self.connection_id = SecureRandom.uuid
    end
  end
end
