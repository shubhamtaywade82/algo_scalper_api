# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: Zeitwerk eager load' do
  it 'eager loads the application without errors' do
    expect { Rails.application.eager_load! }.not_to raise_error
  end
end

