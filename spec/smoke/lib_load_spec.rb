# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Smoke: lib/ loads' do
  it 'loads all lib Ruby source files' do
    lib_paths = Rails.root.glob('lib/**/*.rb')
    expect(lib_paths).not_to be_empty

    lib_paths.each do |path|
      # Exclude scripts/console helpers which may expect interactive context
      # (Rails.root.glob yields Pathname objects — no #include? on them.)
      next if path.to_s.include?('/lib/console/')

      # lib/research scripts are standalone CLI entrypoints: they EXECUTE a
      # research run at load time against the (empty) test DB. Two outcomes are
      # the script working as designed, not load failures:
      # - exit codes (SystemExit) — the CLI's "no data" signal
      # - Research::MarketDataFetcher::SyntheticDataError — strict mode refusing
      #   to fabricate a synthetic dataset when no historical data exists
      # Syntax/constant/dependency errors still fail the smoke check.
      if path.to_s.include?('/lib/research/')
        expect do
          load path
        rescue SystemExit, Research::MarketDataFetcher::SyntheticDataError
          nil
        end.not_to raise_error, "Failed to load lib file: #{path}"
      else
        expect { load path }.not_to raise_error, "Failed to load lib file: #{path}"
      end
    end
  end
end
