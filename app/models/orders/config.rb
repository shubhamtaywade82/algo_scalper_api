# frozen_string_literal: true

module Orders
  class Config
    attr_accessor :gateway

    def initialize(gateway:)
      @gateway = gateway
    end
  end
end
