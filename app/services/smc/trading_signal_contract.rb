# frozen_string_literal: true

module Smc
  # Assembles the versioned JSON contract (structure + triggers + decision + execution shell).
  # Strike selection and broker execution remain outside this class (existing gateways).
  class TradingSignalContract
    VERSION = '1.0'

    class << self
      def publish!(series_5m:, series_15m:, symbol:, ltp:, correlation_id: nil, timeframe: '5m')
        result = build(
          series_5m: series_5m,
          series_15m: series_15m,
          symbol: symbol,
          ltp: ltp,
          correlation_id: correlation_id,
          timeframe: timeframe
        )

        EventStore::Publisher.publish!(
          stream: "#{symbol.to_s.upcase}-#{timeframe}",
          event_type: 'signal',
          correlation_id: result[:correlation_id],
          payload: result[:payload]
        )
        result
      end

      def build(series_5m:, series_15m:, symbol:, ltp:, correlation_id: nil, timeframe: '5m')
        correlation_id ||= SecureRandom.uuid
        price = ltp.to_f

        structure_state = Smc::StructureEngine.new(series_5m).call
        zones = Smc::ZoneEngine.new(series_5m).call(price: price)
        liquidity = Smc::LiquidityEngine.new(series_5m).call
        displacement = Smc::DisplacementEngine.new(series_5m).call
        volume = Smc::VolumeEngine.new(series_5m).call
        mtf = Smc::MtfBiasEngine.new(series_5m: series_5m, series_15m: series_15m).call

        entry = Trading::EntryEngine.new(
          structure: structure_state,
          liquidity: liquidity,
          zones: zones,
          price: price,
          displacement: displacement,
          volume: volume,
          mtf: mtf
        ).call

        payload = compose_payload(
          series_5m: series_5m,
          correlation_id: correlation_id,
          symbol: symbol,
          timeframe: timeframe,
          ltp: price,
          structure_state: structure_state,
          zones: zones,
          liquidity: liquidity,
          displacement: displacement,
          volume: volume,
          mtf: mtf,
          entry: entry
        )

        { payload: payload, entry: entry, correlation_id: correlation_id }
      end

      private

      def compose_payload(series_5m:, correlation_id:, symbol:, timeframe:, ltp:, structure_state:,
                          zones:, liquidity:, displacement:, volume:, mtf:, entry:)
        last_vol = series_5m&.candles&.last&.volume.to_i
        {
          'meta' => {
            'version' => VERSION,
            'timestamp' => Time.zone.now.iso8601,
            'correlation_id' => correlation_id
          },
          'market' => {
            'symbol' => symbol.to_s.upcase,
            'timeframe' => timeframe,
            'ltp' => ltp,
            'volume' => last_vol
          },
          'structure' => structure_section(structure_state),
          'zones' => zones_section(zones),
          'signals' => signals_section(liquidity, displacement, volume, mtf),
          'decision' => decision_section(entry, mtf, liquidity, displacement, volume, zones),
          'execution' => execution_section(entry)
        }
      end

      def structure_section(state)
        {
          'trend' => state.trend.to_s,
          'bos' => {
            'active' => state.last_bos.present?,
            'level' => state.last_bos
          },
          'choch' => {
            'active' => state.last_choch.present?,
            'level' => state.last_choch
          },
          'swing_points' => {
            'hh' => state.hh,
            'hl' => state.hl,
            'lh' => state.lh,
            'll' => state.ll
          }
        }
      end

      def zones_section(zones)
        prem = zones[:premium]
        disc = zones[:discount]
        {
          'premium' => range_to_h(prem),
          'discount' => range_to_h(disc),
          'equilibrium' => zones[:equilibrium],
          'location' => (zones[:location] || 'equilibrium').to_s
        }
      end

      def range_to_h(range)
        return nil unless range.is_a?(Range)

        { 'low' => range.begin.to_f, 'high' => range.end.to_f }
      end

      def signals_section(liquidity, displacement, volume, mtf)
        {
          'liquidity' => {
            'type' => liquidity ? liquidity.type.to_s : 'none',
            'level' => liquidity&.level,
            'strength' => liquidity&.strength
          },
          'displacement' => {
            'bullish' => displacement.bullish,
            'bearish' => displacement.bearish,
            'atr' => displacement.atr,
            'body' => displacement.body
          },
          'volume' => {
            'spike' => volume.spike,
            'ratio' => round4(volume.ratio)
          },
          'mtf' => {
            'bias' => mtf.bias.to_s,
            'valid' => mtf.valid
          }
        }
      end

      def decision_section(entry, mtf, liquidity, displacement, volume, zones)
        if entry
          return {
            'action' => entry.action,
            'confidence' => 0.82,
            'reason' => entry.reason
          }
        end

        {
          'action' => 'NO_TRADE',
          'confidence' => 0.3,
          'reason' => no_trade_reason(mtf, liquidity, displacement, volume, zones)
        }
      end

      def no_trade_reason(mtf, liquidity, displacement, volume, zones)
        return 'no_mtf_alignment' unless mtf.valid
        return 'mid_range' if zones[:location] == :equilibrium

        return 'no_liquidity_event' if liquidity.nil?
        return 'no_displacement' unless displacement.bullish || displacement.bearish
        return 'low_volume' unless volume.spike

        'insufficient_rr'
      end

      def execution_section(entry)
        return { 'valid' => false, 'instrument' => nil, 'order' => nil } unless entry

        {
          'valid' => true,
          'instrument' => nil,
          'order' => {
            'entry_price' => nil,
            'stop_loss' => entry.sl,
            'target' => entry.target,
            'rr' => round4(entry.rr)
          }
        }
      end

      def round4(x)
        x.to_f.round(4)
      end
    end
  end
end
