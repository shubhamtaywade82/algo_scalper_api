# frozen_string_literal: true

# Gemfile loads only debug/prelude, which never opens a remote socket. Open it for
# debug-mcp, but only in the server process: rake tasks, the trading daemon and
# ask-rails-harness-mcp boot Rails too and would each open a competing session.
if Rails.env.development? && ENV['RUBY_DEBUG_OPEN'] == 'true' && defined?(Rails::Server)
  require 'debug/open_nonstop'
end
