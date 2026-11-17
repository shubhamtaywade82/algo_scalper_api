# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::SharedRateLimit do
  let(:limiter_class) do
    Class.new do
      prepend Dhan::SharedRateLimit

      def initialize(api_type) = @api_type = api_type
      def throttle! = :inner_called
    end
  end
  let(:redis) { instance_double(Redis) }

  before { allow(described_class).to receive(:redis).and_return(redis) }

  it 'sleeps until the reserved slot, then runs the in-process limiter' do
    limiter = limiter_class.new(:option_chain)
    allow(redis).to receive(:eval).and_return((Time.now.to_f + 2.0).to_s)
    allow(limiter).to receive(:sleep)

    expect(limiter.throttle!).to eq(:inner_called)
    expect(limiter).to have_received(:sleep).with(be_within(0.2).of(2.0))
  end

  it 'does not sleep when the slot is free' do
    limiter = limiter_class.new(:quote_api)
    allow(redis).to receive(:eval).and_return((Time.now.to_f - 1).to_s)
    allow(limiter).to receive(:sleep)

    limiter.throttle!

    expect(limiter).not_to have_received(:sleep)
  end

  it 'caps the wait so a far-future slot cannot stall a caller' do
    limiter = limiter_class.new(:quote_api)
    allow(redis).to receive(:eval).and_return((Time.now.to_f + 600).to_s)
    allow(limiter).to receive(:sleep)

    limiter.throttle!

    expect(limiter).to have_received(:sleep).with(described_class::MAX_WAIT_SECONDS)
  end

  it 'fails open when Redis is down' do
    limiter = limiter_class.new(:option_chain)
    allow(redis).to receive(:eval).and_raise(Redis::CannotConnectError)

    expect(limiter.throttle!).to eq(:inner_called)
  end

  it 'ignores API types without a configured gap' do
    limiter = limiter_class.new(:order_api)
    allow(redis).to receive(:eval)

    limiter.throttle!

    expect(redis).not_to have_received(:eval)
  end
end
