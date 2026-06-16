# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuyingSignalEvent do
  def build_event(attrs = {})
    described_class.new({
      index_key: 'NIFTY',
      event_type: 'breakout_armed_ce',
      occurred_at: Time.current,
      metadata: {}
    }.merge(attrs))
  end

  it 'is valid with an empty metadata hash (the column default)' do
    expect(build_event(metadata: {})).to be_valid
  end

  it 'is valid with populated metadata' do
    expect(build_event(metadata: { spot_ltp: 24_500 })).to be_valid
  end

  it 'requires index_key, event_type and occurred_at' do
    expect(build_event(index_key: nil)).not_to be_valid
    expect(build_event(event_type: nil)).not_to be_valid
    expect(build_event(occurred_at: nil)).not_to be_valid
  end
end
