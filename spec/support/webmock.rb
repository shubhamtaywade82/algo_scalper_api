# frozen_string_literal: true

require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before(:each) do
    # Fallback stub for Dhan TOTP authentication so tests without a cassette
    # never leak live HTTP calls to broker or fail with unhandled request errors.
    stub_request(:post, %r{\Ahttps://auth\.dhan\.co/app/generateAccessToken})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          'status' => 'success',
          'accessToken' => 'test-mock-access-token',
          'expiryTime' => 1.day.from_now.iso8601
        }.to_json
      )
  end
end
