# frozen_string_literal: true

# ApplicationAgent - base class for all agents in this application, built on
# RubyLLM's native RubyLLM::Agent (ruby_llm 2.x, https://rubyllm.com/agents/).
#
# Quick reference:
#   class MyAgent < ApplicationAgent
#     inputs :query
#     input_defaults query: "status"            # optional defaults for declared inputs
#     instructions "You are a helpful assistant."
#     user_prompt "Answer this: %<query>s"      # %<input>s placeholders, rendered per call
#     schema do                                 # structured output (Schematist DSL)
#       string :answer, description: "The answer"
#     end
#   end
#
# Usage:
#   MyAgent.call(query: "hello")                 # => parsed schema Hash
#   MyAgent.new(query: "hello").ask("...")       # => RubyLLM::Message (full control)
#
# Provider/model come from LLMSettings (Ollama local or Ollama Cloud). Request
# timeouts and transient-error retries are configured globally in
# config/initializers/ruby_llm.rb.
class ApplicationAgent < RubyLLM::Agent
  # Raised when a structured agent's reply is not valid JSON for its schema.
  class InvalidResponseError < StandardError; end

  model(provider: LLMSettings.provider) { LLMSettings.default_model }

  class << self
    # The user-turn template; %<name>s placeholders are filled from inputs.
    def user_prompt(template = nil)
      return @user_prompt || (superclass.user_prompt if superclass.respond_to?(:user_prompt)) if template.nil?

      @user_prompt = template
    end

    def input_defaults(**defaults)
      return @input_defaults || {} if defaults.empty?

      @input_defaults = defaults
    end

    # Runs one turn (including any tool calls) and returns the parsed
    # structured output Hash.
    def call(**provided)
      values = input_defaults.merge(provided.compact)
      missing = inputs - values.keys
      raise ArgumentError, "#{name}: missing inputs #{missing.join(', ')}" if missing.any?
      raise ArgumentError, "#{name}: user_prompt is not defined" if user_prompt.blank?

      message = new(**values).ask(format(user_prompt, **values))
      return message.content if schema.nil?

      message.parsed || raise(InvalidResponseError, "#{name}: empty structured response")
    rescue JSON::ParserError => e
      raise InvalidResponseError, "#{name}: response is not valid JSON (#{e.message.truncate(120)})"
    end
  end
end
