# frozen_string_literal: true

module Orders
  class Config
    attr_reader :gateway

    def initialize(gateway:)
      @gateway = gateway
    end
  end
end
