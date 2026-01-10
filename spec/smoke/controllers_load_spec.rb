# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: Controllers load' do
  it 'loads all controller source files' do
    controller_paths = Dir[Rails.root.join('app/controllers/**/*.rb')].sort
    expect(controller_paths).not_to be_empty

    controller_paths.each do |path|
      expect { load path }.not_to raise_error, "Failed to load controller file: #{path}"
    end
  end
end

