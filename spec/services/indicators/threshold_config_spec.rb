# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::ThresholdConfig do
  describe '.get_preset' do
    it 'returns loose preset' do
      preset = described_class.get_preset(:loose)
      expect(preset).to be_a(Hash)
      expect(preset[:adx][:min_strength]).to eq(10)
      expect(preset[:multi_indicator][:min_confidence]).to eq(40)
    end

    it 'returns moderate preset by default' do
      preset = described_class.get_preset
      expect(preset[:adx][:min_strength]).to eq(15)
    end

    it 'returns moderate preset for unknown preset' do
      preset = described_class.get_preset(:unknown)
      expect(preset[:adx][:min_strength]).to eq(15)
    end
  end

  describe '.current_preset' do
    it 'returns preset from ENV' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('INDICATOR_PRESET').and_return('tight')
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: {} })
      expect(described_class.current_preset).to eq(:tight)
    end

    it 'returns preset from config' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('INDICATOR_PRESET').and_return(nil)
      allow(AlgoConfig).to receive(:fetch).and_return({
        signals: { indicator_preset: :loose }
      })
      expect(described_class.current_preset).to eq(:loose)
    end

    it 'defaults to moderate' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('INDICATOR_PRESET').and_return(nil)
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: {} })
      expect(described_class.current_preset).to eq(:moderate)
    end
  end

  describe '.for_indicator' do
    it 'returns thresholds for ADX' do
      thresholds = described_class.for_indicator(:adx, :loose)
      expect(thresholds[:min_strength]).to eq(10)
    end

    it 'uses current preset when not specified' do
      allow(described_class).to receive(:current_preset).and_return(:tight)
      thresholds = described_class.for_indicator(:adx)
      expect(thresholds[:min_strength]).to eq(25)
    end
  end

  describe '.merge_with_thresholds' do
    it 'merges base config with threshold config' do
      base_config = { period: 14 }
      merged = described_class.merge_with_thresholds(:adx, base_config, :loose)
      expect(merged[:period]).to eq(14)
      expect(merged[:min_strength]).to eq(10)
    end

    it 'preserves base config values over threshold values' do
      base_config = { min_strength: 18 }
      merged = described_class.merge_with_thresholds(:adx, base_config, :loose)
      expect(merged[:min_strength]).to eq(18) # Base config takes precedence
    end
  end

  describe '.available_presets' do
    it 'returns all preset names' do
      presets = described_class.available_presets
      expect(presets).to include(:loose, :moderate, :tight, :production)
    end
  end

  describe '.preset_exists?' do
    it 'returns true for valid preset' do
      expect(described_class.preset_exists?(:loose)).to be true
    end

    it 'returns false for invalid preset' do
      expect(described_class.preset_exists?(:invalid)).to be false
    end
  end
end
