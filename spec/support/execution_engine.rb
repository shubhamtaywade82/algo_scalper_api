# frozen_string_literal: true

# config/algo.yml runs the agent engine (Rails forwards entries to options-trading-agent). Specs exercise the Rails
# entry path unless they opt in by stubbing TradeIntents::Forwarder.agent_engine? themselves or tagging
# :real_execution_engine to read the real config.
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:real_execution_engine]

    allow(TradeIntents::Forwarder).to receive(:agent_engine?).and_return(false)
  end
end
