# frozen_string_literal: true

require 'rails_helper'

# ruby_llm-agents used to register the "LLM" acronym globally. After moving to
# RubyLLM 2.x native agents the app owns it; losing it breaks Zeitwerk
# constant resolution and production eager loading.
RSpec.describe 'Inflections' do # rubocop:disable RSpec/DescribeClass
  it 'keeps LLM as an acronym for autoloaded constants' do
    expect('llm_planner'.camelize).to eq('LLMPlanner')
    expect('llm_settings'.camelize).to eq('LLMSettings')
    expect(Rails.autoloaders.main.inflector.camelize('llm_planner', nil)).to eq('LLMPlanner')
  end

  it 'resolves the LLM-named app constants' do
    expect(AutoExp::LLMPlanner).to be_a(Class)
    expect(LLMSettings).to be_a(Module)
  end
end
