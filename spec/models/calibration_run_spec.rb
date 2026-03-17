# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'calibration_runs table' do
  it 'has the expected columns' do
    cols = ActiveRecord::Base.connection.columns(:calibration_runs).map(&:name)
    expect(cols).to include(
      'symbol', 'weeks_analyzed', 'strike_mode',
      'raw_stats', 'proposed_patch',
      'is_regime_shift', 'regime_reason',
      'applied_at', 'applied_by',
      'created_at', 'updated_at'
    )
  end
end
