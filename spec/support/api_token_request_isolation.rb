# frozen_string_literal: true

# Request specs assume optional API tokens are unset so auth is not enforced unless an
# example explicitly sets ENV['API_DASHBOARD_TOKEN'] / ENV['API_OPERATOR_TOKEN'].
RSpec.configure do |config|
  config.around(:each, type: :request) do |example|
    dash = ENV.fetch('API_DASHBOARD_TOKEN', nil)
    op = ENV.fetch('API_OPERATOR_TOKEN', nil)
    ENV.delete('API_DASHBOARD_TOKEN')
    ENV.delete('API_OPERATOR_TOKEN')
    example.run
  ensure
    if dash
      ENV['API_DASHBOARD_TOKEN'] = dash
    else
      ENV.delete('API_DASHBOARD_TOKEN')
    end

    if op
      ENV['API_OPERATOR_TOKEN'] = op
    else
      ENV.delete('API_OPERATOR_TOKEN')
    end
  end
end
