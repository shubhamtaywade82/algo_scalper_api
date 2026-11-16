# frozen_string_literal: true

require 'rails_helper'

# Guards the RESTful route table: every API route must map to an existing controller
# action, and no controller may keep a public action that no route reaches.
RSpec.describe 'API route table' do # rubocop:disable RSpec/DescribeClass
  let(:non_action_methods) { %w[render_success render_error serialize_variable] }
  let(:restful_actions) { %w[index show new create edit update destroy] }

  let(:api_routes) do
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller&.start_with?('api/')

      [route.verb, route.path.spec.to_s, controller, route.defaults[:action]]
    end
  end

  before { Rails.application.eager_load! }

  it 'maps every API route to an existing controller action' do
    unresolved = api_routes.reject do |_verb, _path, controller, action|
      "#{controller.camelize}Controller".safe_constantize&.action_methods&.include?(action)
    end

    expect(unresolved).to be_empty
  end

  it 'leaves no unrouted public actions on API controllers' do
    routed = api_routes.group_by { |route| route[2] }.transform_values { |routes| routes.map(&:last) }
    unrouted = routed.keys.filter_map do |controller|
      klass = "#{controller.camelize}Controller".constantize
      extra = klass.action_methods.to_a - routed[controller] - non_action_methods
      [controller, extra] if extra.any?
    end

    expect(unrouted).to be_empty
  end

  it 'uses only the seven RESTful action names' do
    custom = api_routes.reject { |*, action| restful_actions.include?(action) }

    expect(custom).to be_empty
  end
end
