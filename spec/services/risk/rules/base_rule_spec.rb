# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::BaseRule do
  let(:config) { { enabled: true, sl_pct: 2.0 } }
  let(:rule) { described_class.new(config: config) }

  describe '#initialize' do
    it 'sets config' do
      expect(rule.config).to eq(config)
    end

    it 'handles nil config' do
      rule = described_class.new(config: nil)
      expect(rule.config).to eq({})
    end
  end

  describe '#priority' do
    it 'returns class priority' do
      expect(rule.priority).to eq(described_class::PRIORITY)
    end
  end

  describe '#name' do
    it 'returns formatted name' do
      expect(rule.name).to eq('base')
    end
  end

  describe '#enabled?' do
    it 'returns true when enabled in config' do
      expect(rule.enabled?).to be true
    end

    it 'returns false when disabled in config' do
      config[:enabled] = false
      expect(rule.enabled?).to be false
    end

    it 'returns true by default' do
      rule = described_class.new(config: {})
      expect(rule.enabled?).to be true
    end
  end

  describe '#evaluate' do
    it 'raises NotImplementedError' do
      context = instance_double(Risk::Rules::RuleContext)
      expect { rule.evaluate(context) }.to raise_error(NotImplementedError)
    end
  end

  describe 'helper methods' do
    let(:context) { instance_double(Risk::Rules::RuleContext) }

    describe '#exit_result' do
      it 'creates exit result' do
        result = rule.send(:exit_result, reason: 'test')
        expect(result.exit?).to be true
        expect(result.reason).to eq('test')
      end
    end

    describe '#no_action_result' do
      it 'creates no_action result' do
        result = rule.send(:no_action_result)
        expect(result.no_action?).to be true
      end
    end

    describe '#skip_result' do
      it 'creates skip result' do
        result = rule.send(:skip_result)
        expect(result.skip?).to be true
      end
    end
  end
end
