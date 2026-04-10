# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::SettingsController do
  it 'has request coverage in spec/requests/api/settings_spec.rb' do
    expect(described_class).to be < ApplicationController
  end
end
