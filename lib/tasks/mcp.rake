# frozen_string_literal: true

namespace :mcp do
  desc 'Ask a local Ollama model a question answered via the MCP tools (MCP server starts with ./bin/dev)'
  task :ask, [:question] => :environment do |_task, args|
    question = args[:question].presence || abort('usage: bin/rails "mcp:ask[How is NIFTY looking?]"')
    bridge = MCP::OllamaBridge.new(
      token: ENV.fetch('MCP_API_TOKEN', nil),
      url: ENV.fetch('MCP_URL', MCP::OllamaBridge::DEFAULT_URL)
    )
    puts bridge.ask(question)
  end
end
