# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: Services load' do
  it 'loads all service source files' do
    service_paths = Rails.root.glob('app/services/**/*.rb')
    expect(service_paths).not_to be_empty

    service_paths.each do |path|
      expect { load path }.not_to raise_error, "Failed to load service file: #{path}"
    end
  end
end
