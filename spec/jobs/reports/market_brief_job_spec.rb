# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBriefJob do
  before { allow(Reports::MarketBrief::Generator).to receive(:call) }

  it 'builds the requested report' do
    report, = MarketBriefReport.request!(mode: :paper)
    described_class.perform_now(report.id, 'manual', true)
    expect(Reports::MarketBrief::Generator).to have_received(:call).with(report, force_ai: true)
  end

  it 'creates and builds the scheduled report on a trading day' do
    allow(Market::Calendar).to receive(:trading_day?).and_return(true)
    expect { described_class.perform_now(nil, 'scheduled') }.to change(MarketBriefReport, :count).by(1)
    expect(MarketBriefReport.last).to have_attributes(trigger: 'scheduled', mode: 'paper')
    expect(Reports::MarketBrief::Generator).to have_received(:call).with(MarketBriefReport.last, force_ai: false)
  end

  it 'does nothing on a non-trading day' do
    allow(Market::Calendar).to receive(:trading_day?).and_return(false)
    expect { described_class.perform_now(nil, 'scheduled') }.not_to change(MarketBriefReport, :count)
    expect(Reports::MarketBrief::Generator).not_to have_received(:call)
  end

  it 'discards a job whose report was deleted' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'is scheduled through Solid Queue recurring config with positional args' do
    config = YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true)
    %w[development production].each do |env|
      expect(config.dig(env, 'market_brief_opening')).to include('class' => 'Reports::MarketBriefJob', 'args' => [nil, 'scheduled'])
    end
  end
end
