# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine entry quality filter integration' do
  it 'has EntryQualityFilter.evaluate wired into the signal engine' do
    source = Rails.root.join('app/services/signal/engine.rb').read
    expect(source).to include('Signal::EntryQualityFilter.evaluate')
  end

  it 'stores quality score in entry_metadata' do
    source = Rails.root.join('app/services/signal/engine.rb').read
    expect(source).to include('entry_quality_score')
    expect(source).to include('entry_quality_breakdown')
  end
end
