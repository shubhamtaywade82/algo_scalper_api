# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PositionTracker do
  describe 'association contracts' do
    it 'requires instrument association explicitly' do
      options = described_class.reflect_on_association(:instrument).options
      expect(options[:optional]).to be(false)
    end

    it 'declares trade telemetry association' do
      association = described_class.reflect_on_association(:trade_telemetry)
      expect(association).not_to be_nil
      expect(association.class_name).to eq('TradeTelemetry')
    end

    it 'requires derivative instrument association explicitly' do
      options = Derivative.reflect_on_association(:instrument).options
      expect(options[:optional]).to be(false)
    end

    it 'requires trade analytic position tracker association explicitly' do
      options = TradeAnalytic.reflect_on_association(:position_tracker).options
      expect(options[:optional]).to be(false)
    end

    it 'requires trade telemetry tracker association explicitly' do
      options = TradeTelemetry.reflect_on_association(:tracker).options
      expect(options[:optional]).to be(false)
    end

    it 'requires best indicator param instrument association explicitly' do
      options = BestIndicatorParam.reflect_on_association(:instrument).options
      expect(options[:optional]).to be(false)
    end
  end
end
