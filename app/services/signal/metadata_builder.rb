# frozen_string_literal: true

module Signal
  class MetadataBuilder
    class << self
      def build(params)
        signals_cfg = params[:signals_cfg]
        options_analysis = params[:options_analysis]
        primary_analysis = params[:primary_analysis]
        
        {
          # Market State Diagnostics
          regime: params[:regime],
          regime_confidence: params[:regime_result]&.[](:confidence) || 0,
          regime_metrics: params[:regime_result]&.[](:metrics) || {},

          # Multi-Timeframe Diagnostics
          ta_signal: params[:ta_result]&.dig(:signal),
          ta_confidence: params[:ta_result]&.dig(:confidence),
          ta_bias: params[:ta_result]&.dig(:bias_summary, :summary, :bias),
          mtf_rsi: params[:ta_result]&.dig(:indicators)&.transform_values { |v| v[:rsi] },
          mtf_macd: params[:ta_result]&.dig(:indicators)&.transform_values { |v| v[:macd] },
          mtf_atr: params[:ta_result]&.dig(:indicators)&.transform_values { |v| v[:atr] },

          # Options Behavior / Greeks
          gamma_pressure: options_analysis&.dig(:gamma_pressure, :score),
          gamma_ramp_strike: options_analysis&.dig(:gamma_pressure, :strike),
          iv_rank_proxy: options_analysis&.dig(:iv_rank, :iv_rank_proxy),
          theta_risk_score: options_analysis&.dig(:theta_risk, :risk_score),
          expiry_blocked: options_analysis&.dig(:expiry_blocked),

          # Execution Context
          entry_path: build_entry_path_identifier(params),
          strategy: params[:strategy_name] || 'supertrend_adx',
          strategy_mode: params[:strategy_mode] || 'supertrend_adx',
          primary_timeframe: params[:primary_tf],
          effective_timeframe: params[:effective_timeframe],
          confirmation_timeframe: params[:confirmation_tf],
          confirmation_enabled: params[:enable_confirmation],
          confirmation_direction: params[:confirmation_analysis]&.dig(:direction),
          validation_mode: params[:effective_validation_mode] || signals_cfg[:validation_mode] || 'balanced',
          validation_passed: params[:validation_result]&.[](:valid),
          state_count: params[:state_snapshot]&.[](:count),
          state_multiplier: params[:state_snapshot]&.[](:multiplier),
          original_timeframe: params[:primary_tf],

          # Signal Indicators
          adx_value: primary_analysis[:adx_value],

          # SMC/Permission integration
          smc_decision: params[:smc_decision].to_s,
          smc_permission: params[:permission].to_s
        }
      end

      private

      def build_entry_path_identifier(params)
        strategy_name = params[:strategy_name] || 'supertrend_adx'
        tf_label = params[:effective_timeframe]
        conf_label = params[:enable_confirmation] ? "+#{params[:confirmation_tf]}" : ''
        
        "#{strategy_name}[#{tf_label}#{conf_label}]"
      end
    end
  end
end
