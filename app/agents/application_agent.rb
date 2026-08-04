# frozen_string_literal: true

# ApplicationAgent - Base class for all agents in this application
#
# All agents inherit from this class. Configure shared settings here.
#
# Quick reference:
#   class MyAgent < ApplicationAgent
#     system "You are a helpful assistant."
#     prompt "Answer this: {query}"          # {query} becomes a required param
#
#     returns do                             # Optional: structured output
#       string :answer, description: "The answer"
#     end
#   end
#
# Usage:
#   MyAgent.call(query: "hello")
#   MyAgent.call(query: "hello", dry_run: true)    # Debug mode
#   MyAgent.call(query: "hello", skip_cache: true) # Bypass cache
#
class ApplicationAgent < RubyLLM::Agents::Base
  # Shared settings inherited by all agents.
  # Override per-agent as needed.

  # model "gpt-4o"              # Override the configured default model
  # temperature 0.0             # 0.0 = deterministic, 2.0 = creative
  # cache for: 1.hour           # Enable caching for all agents

  # Retry on transient cloud errors (empty body, rate-limit, timeout).
  on_failure do
    retries times: 3, backoff: :exponential
    timeout 60
  end
end
