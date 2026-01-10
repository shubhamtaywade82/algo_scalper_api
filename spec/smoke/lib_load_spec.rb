# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: lib/ loads' do
  it 'loads all lib Ruby source files' do
    lib_paths = Rails.root.glob('lib/**/*.rb')
    expect(lib_paths).not_to be_empty

    lib_paths.each do |path|
      # Exclude scripts/console helpers which may expect interactive context
      next if path.include?('/lib/console/')

      expect { load path }.not_to raise_error, "Failed to load lib file: #{path}"
    end
  end
end
