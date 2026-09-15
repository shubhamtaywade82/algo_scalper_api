# frozen_string_literal: true

require 'rails_helper'

# Strictness contract for safety-critical config reads (error-handling
# review 2026-09): "unknown" must never be reported as "off" or "production".
RSpec.describe AlgoConfig do
  describe '.paper_trading_enabled?' do
    it 'returns the explicit value when configured' do
      allow(described_class).to receive(:fetch).and_return(paper_trading: { enabled: false })
      expect(described_class.paper_trading_enabled?).to be(false)

      allow(described_class).to receive(:fetch).and_return(paper_trading: { enabled: true })
      expect(described_class.paper_trading_enabled?).to be(true)
    end

    it 'keeps the legacy enabled default in test env (partial fetch stubs)' do
      allow(described_class).to receive(:fetch).and_return({})
      expect(described_class.paper_trading_enabled?).to be(true)
    end

    it 'refuses to guess outside the test environment' do
      allow(described_class).to receive(:fetch).and_return({})
      allow(Rails.env).to receive(:test?).and_return(false)

      expect { described_class.paper_trading_enabled? }
        .to raise_error(Errors::ConfigurationError, /paper_trading\.enabled must be explicitly true or false/)
    end

    it 'refuses non-boolean values outside the test environment' do
      allow(described_class).to receive(:fetch).and_return(paper_trading: { enabled: 'yes' })
      allow(Rails.env).to receive(:test?).and_return(false)

      expect { described_class.paper_trading_enabled? }
        .to raise_error(Errors::ConfigurationError, /refusing to guess/)
    end
  end

  describe '.run_mode' do
    it 'returns the configured mode' do
      allow(described_class).to receive(:fetch).and_return(run_mode: 'exit_testing')
      expect(described_class.run_mode).to eq('exit_testing')
    end

    it 'prefers the ENV override' do
      allow(ENV).to receive(:[]).with('RUN_MODE').and_return('entry_testing')
      expect(described_class.run_mode).to eq('entry_testing')
    end

    it 'keeps the legacy production default in test env' do
      allow(described_class).to receive(:fetch).and_return({})
      expect(described_class.run_mode).to eq('production')
    end

    it 'refuses to guess outside the test environment' do
      allow(described_class).to receive(:fetch).and_return({})
      allow(Rails.env).to receive(:test?).and_return(false)

      expect { described_class.run_mode }
        .to raise_error(Errors::ConfigurationError, /run_mode is not configured/)
    end
  end

  describe '.apply_profile' do
    it 'raises Errors::ConfigurationError when the profile YAML is corrupt' do
      allow(described_class).to receive(:run_mode).and_return('production')
      path = Rails.root.join('config/profiles/production.yml')
      allow(File).to receive(:file?).and_call_original
      allow(path).to receive(:file?).and_return(true)
      allow(YAML).to receive(:load_file).with(path).and_raise(Psych::SyntaxError.new(1, 1, 1, 1, 'bad', 'yaml'))

      expect { described_class.send(:apply_profile, { run_mode: 'production' }) }
        .to raise_error(Errors::ConfigurationError, /profile config\/production\.yml is unreadable/)
    end

    it 'raises when the profile does not parse to a Hash' do
      allow(described_class).to receive(:run_mode).and_return('production')
      path = Rails.root.join('config/profiles/production.yml')
      allow(File).to receive(:file?).and_call_original
      allow(path).to receive(:file?).and_return(true)
      allow(YAML).to receive(:load_file).with(path).and_return(['not', 'a', 'hash'])

      expect { described_class.send(:apply_profile, { run_mode: 'production' }) }
        .to raise_error(Errors::ConfigurationError, /did not parse to a Hash/)
    end

    it 'passes through base config when the profile file is absent' do
      allow(described_class).to receive(:run_mode).and_return('production')
      path = Rails.root.join('config/profiles/production.yml')
      allow(File).to receive(:file?).and_call_original
      allow(path).to receive(:file?).and_return(false)

      result = described_class.send(:apply_profile, { run_mode: 'production', risk: { x: 1 } })
      expect(result).to include(run_mode: 'production', risk: { x: 1 })
    end
  end
end
