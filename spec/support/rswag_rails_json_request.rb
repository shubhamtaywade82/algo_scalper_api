# frozen_string_literal: true

# RSwag passes JSON bodies as strings via +params:+, which Rails integration tests do not
# decode into +params[:settings]+. Parse JSON and submit with +as: :json+.
require 'rswag/specs'

Rswag::Specs::ExampleHelpers.module_eval do
  def submit_request(metadata)
    request = Rswag::Specs::RequestFactory.new.build_request(metadata, self)
    payload = request[:payload]
    headers = request[:headers] || {}

    if payload.is_a?(String) && headers['CONTENT_TYPE'].to_s.include?('application/json')
      parsed = JSON.parse(payload)
      hdrs = headers.except('CONTENT_TYPE')
      send(
        request[:verb],
        request[:path],
        params: parsed,
        headers: hdrs,
        as: :json
      )
      return
    end

    if Rswag::Specs::RAILS_VERSION < 5
      send(request[:verb], request[:path], request[:payload], request[:headers])
    else
      send(request[:verb], request[:path], params: request[:payload], headers: request[:headers])
    end
  end
end
