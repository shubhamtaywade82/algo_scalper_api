# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: Services load' do
  it 'loads all service source files' do
    service_paths = Rails.root.glob('app/services/**/*.rb')
    expect(service_paths).not_to be_empty

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
        # The child shares the parent's DB sockets; drop them so anything
        # that executes at load time reconnects on its own connection.
        ActiveRecord::Base.connection_pool.disconnect!
      rescue StandardError
        nil
      end
      service_paths.each do |path|
        load path
      rescue StandardError => e
        failures << "#{path}: #{e.class}: #{e.message}"
      end
      warn failures.join("\n") if failures.any?
      exit!(failures.empty?)
    end
    _waited, status = Process.wait2(pid)
    expect(status.success?).to be(true)
  end
end
