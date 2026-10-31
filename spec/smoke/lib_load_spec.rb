# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: lib/ loads' do
  it 'loads all lib Ruby source files' do
    lib_paths = Rails.root.glob('lib/**/*.rb')
    expect(lib_paths).not_to be_empty

    # Exclude scripts/console helpers which may expect interactive context
    # (Rails.root.glob yields Pathname objects — no #include? on them.)
    lib_paths = lib_paths.reject { |path| path.to_s.include?('/lib/console/') }

    # Run the raw `load` checks in a forked child. Re-loading a file resets
    # Ruby's per-file Coverage counters, which previously wiped ALL coverage
    # accumulated by earlier specs in this process and made SimpleCov
    # under-report the whole suite. The child's counter resets die with the
    # child; the parent's SimpleCov resultset is untouched.
    pid = fork do
      failures = []
      # Re-loads re-define constants; silence the benign "already
      # initialized" warnings so CI logs stay readable.
      $VERBOSE = nil
      begin
        # The child shares the parent's DB sockets; drop them so the research
        # scripts below (which execute a run at load time) reconnect on their
        # own connection instead of interleaving with the parent's.
        ActiveRecord::Base.connection_pool.disconnect!
      rescue StandardError
        nil
      end

      lib_paths.each do |path|
        # lib/research scripts are standalone CLI entrypoints: they EXECUTE a
        # research run at load time against the (empty) test DB. Two outcomes
        # are the script working as designed, not load failures:
        # - exit codes (SystemExit) — the CLI's "no data" signal
        # - Research::MarketDataFetcher::SyntheticDataError — strict mode
        #   refusing to fabricate a synthetic dataset when no data exists
        # Syntax/constant/dependency errors still fail the smoke check.
        if path.to_s.include?('/lib/research/')
          begin
            load path
          rescue SystemExit, Research::MarketDataFetcher::SyntheticDataError
            nil
          rescue StandardError => e
            failures << "#{path}: #{e.class}: #{e.message}"
          end
        else
          begin
            load path
          rescue StandardError => e
            failures << "#{path}: #{e.class}: #{e.message}"
          end
        end
      end

      warn failures.join("\n") if failures.any?
      exit!(failures.empty?)
    end
    _waited, status = Process.wait2(pid)
    expect(status.success?).to be(true)
  end
end
