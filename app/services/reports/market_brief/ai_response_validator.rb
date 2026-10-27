# frozen_string_literal: true

module Reports
  module MarketBrief
    # Deterministic post-validation of the LLM interpretation.
    #
    # Guarantees on a :valid result:
    #   * the payload matches the v1 structure (unknown keys discarded, lengths bounded)
    #   * every evidence source_key resolves to a path in the facts the model was shown
    #   * every number in free text appears in those facts (else the field is dropped)
    #   * the model cannot alter the deterministic setup decision: a setup explanation
    #     is only kept when setup.decision == QUALIFIED, otherwise only a no-trade one
    #   * a directional bias is only kept when backed by at least one valid evidence item
    #   * disagreements with the deterministic technical/SMC bias are surfaced, not resolved
    #
    # Nothing produced here is ever executable: there are no price/quantity fields.
    class AiResponseValidator
      BIASES = %w[BULLISH BEARISH MIXED NEUTRAL UNAVAILABLE].freeze
      MAX_RAW_BYTES = 64.kilobytes
      LIMITS = { summary: 600, text: 280, evidence: 5, conflicts: 3, list: 4 }.freeze
      # Small counts ("three timeframes", "2 rejections") are not market facts.
      FREE_INTEGER_RANGE = (0..10)
      NUMBER_PATTERN = /-?\d[\d,]*(?:\.\d+)?/
      OPPOSING_BIAS = { 'BULLISH' => 'BEARISH', 'BEARISH' => 'BULLISH' }.freeze

      Result = Data.define(:status, :analysis, :errors) do
        def valid?
          status == :valid
        end
      end

      def initialize(snapshot)
        @facts = AiPromptBuilder.facts(snapshot)
        @index_keys = @facts['indices'].keys
        @decision = @facts.dig('setup', 'decision')
        @allowed_numbers = Set.new
        collect_numbers(@facts)
        @dropped = []
      end

      def call(raw)
        data = parse(raw)
        return invalid('unparseable_json') unless data.is_a?(Hash)
        return invalid('schema_version_mismatch') unless data['schema_version'].to_i == AiPromptBuilder::OUTPUT_SCHEMA_VERSION

        summary = clean_text(data['executive_summary'], LIMITS[:summary], 'executive_summary')
        return invalid('executive_summary_missing_or_unsupported') if summary.blank?

        indices = validate_indices(data['indices'])
        kept_evidence = indices.sum { |i| i['evidence'].size }
        dropped_evidence = @dropped.count { |d| d[:field].include?('.evidence') }
        if dropped_evidence > kept_evidence
          return invalid("too_many_unsupported_references (#{dropped_evidence} dropped, #{kept_evidence} kept)")
        end

        setup_explanation, no_trade_explanation = validate_setup_text(data)

        analysis = {
          'schema_version' => AiPromptBuilder::OUTPUT_SCHEMA_VERSION,
          'executive_summary' => summary,
          'indices' => indices,
          'setup_explanation' => setup_explanation,
          'no_trade_explanation' => no_trade_explanation,
          'key_risks' => clean_list(data['key_risks'], 'key_risks'),
          'limitations' => clean_list(data['limitations'], 'limitations'),
          'disagreements' => disagreements(indices),
          'validation' => { 'dropped' => @dropped.map(&:stringify_keys) }
        }
        Result.new(status: :valid, analysis: analysis, errors: [])
      end

      private

      # ------------------------------------------------------------------
      # Parsing
      # ------------------------------------------------------------------

      def parse(raw)
        text = raw.to_s
        return nil if text.strip.empty? || text.bytesize > MAX_RAW_BYTES

        text = text.gsub(/```(?:json)?/i, '').strip
        start = text.index('{')
        finish = text.rindex('}')
        return nil unless start && finish && finish > start

        JSON.parse(text[start..finish])
      rescue JSON::ParserError
        nil
      end

      def invalid(reason)
        Result.new(status: :invalid, analysis: nil, errors: [reason])
      end

      # ------------------------------------------------------------------
      # Sections
      # ------------------------------------------------------------------

      def validate_indices(raw)
        seen = Set.new
        Array(raw).filter_map do |entry|
          next unless entry.is_a?(Hash)

          key = entry['index_key'].to_s.upcase
          unless @index_keys.include?(key) && seen.add?(key)
            drop('indices', "unknown_or_duplicate_index:#{key.truncate(20)}")
            next
          end

          field = "indices.#{key}"
          evidence = Array(entry['evidence']).first(LIMITS[:evidence]).filter_map { |e| validate_evidence(e, field) }
          bias = entry['bias'].to_s.upcase
          bias = 'UNAVAILABLE' unless BIASES.include?(bias)
          if evidence.empty? && bias != 'UNAVAILABLE'
            drop("#{field}.bias", 'bias_without_valid_evidence')
            bias = 'UNAVAILABLE'
          end

          {
            'index_key' => key,
            'bias' => bias,
            'evidence' => evidence,
            'conflicts' => Array(entry['conflicts']).first(LIMITS[:conflicts])
                                                    .filter_map { |c| clean_text(c, LIMITS[:text], "#{field}.conflicts") },
            'bullish_scenario' => scenario(entry['bullish_scenario'], "#{field}.bullish_scenario"),
            'bearish_scenario' => scenario(entry['bearish_scenario'], "#{field}.bearish_scenario")
          }
        end
      end

      def validate_evidence(item, field)
        return drop("#{field}.evidence", 'malformed_evidence') unless item.is_a?(Hash)

        source_key = item['source_key'].to_s.strip
        unless resolvable?(source_key)
          return drop("#{field}.evidence", "unknown_source_key:#{source_key.truncate(80)}")
        end

        observation = clean_text(item['observation'], LIMITS[:text], "#{field}.evidence")
        return nil if observation.blank?

        { 'observation' => observation, 'source_key' => source_key }
      end

      def scenario(raw, field)
        return nil unless raw.is_a?(Hash)

        condition = clean_text(raw['condition'], LIMITS[:text], field)
        invalidation = clean_text(raw['invalidation'], LIMITS[:text], field)
        return nil if condition.blank? || invalidation.blank?

        { 'condition' => condition, 'invalidation' => invalidation }
      end

      # The deterministic decision is final; the model only explains it.
      def validate_setup_text(data)
        qualified = @decision == 'QUALIFIED'
        setup = clean_text(data['setup_explanation'], LIMITS[:summary], 'setup_explanation')
        no_trade = clean_text(data['no_trade_explanation'], LIMITS[:summary], 'no_trade_explanation')

        if qualified && no_trade.present?
          drop('no_trade_explanation', 'contradicts_deterministic_decision')
          no_trade = nil
        end
        if !qualified && setup.present?
          drop('setup_explanation', 'contradicts_deterministic_decision')
          setup = nil
        end
        [setup, no_trade]
      end

      def disagreements(indices)
        indices.filter_map do |entry|
          det = @facts.dig('indices', entry['index_key'], 'bias') || {}
          opposing = OPPOSING_BIAS[entry['bias']]
          next unless opposing
          next unless [det['technical'], det['smc']].include?(opposing)

          {
            'index_key' => entry['index_key'],
            'ai_bias' => entry['bias'],
            'deterministic_technical' => det['technical'],
            'deterministic_smc' => det['smc']
          }
        end
      end

      def clean_list(raw, field)
        Array(raw).first(LIMITS[:list]).filter_map { |t| clean_text(t, LIMITS[:text], field) }
      end

      # ------------------------------------------------------------------
      # Text and number grounding
      # ------------------------------------------------------------------

      def clean_text(value, limit, field)
        return nil unless value.is_a?(String)

        text = value.gsub(/[[:cntrl:]]/, ' ').gsub(/<[^>]*>/, '').squish
        return nil if text.empty?

        unsupported = unsupported_numbers(text)
        if unsupported.any?
          drop(field, "unsupported_numbers:#{unsupported.first(3).join(',')}")
          return nil
        end

        text.truncate(limit)
      end

      def unsupported_numbers(text)
        text.scan(NUMBER_PATTERN).filter_map do |token|
          number = Float(token.delete(','))
          next if number == number.round && FREE_INTEGER_RANGE.cover?(number.abs.to_i)
          next if @allowed_numbers.include?(number.abs.round(2))

          token
        rescue ArgumentError
          nil
        end
      end

      def collect_numbers(value)
        case value
        when Hash then value.each_value { |v| collect_numbers(v) }
        when Array then value.each { |v| collect_numbers(v) }
        when Numeric then allow_number(value)
        when String then value.scan(NUMBER_PATTERN).each { |t| allow_number(Float(t.delete(','), exception: false)) }
        end
      end

      def allow_number(number)
        return unless number.is_a?(Numeric) && number.to_f.finite?

        n = number.to_f.abs
        [0, 1, 2].each { |precision| @allowed_numbers << n.round(precision).round(2) }
        # Ratios stored as decimals (atr_percent 0.0042, limit_pct 0.03) may be quoted as percents.
        [0, 1, 2].each { |precision| @allowed_numbers << (n * 100).round(precision).round(2) } if n < 1
      end

      def resolvable?(path)
        return false if path.blank? || path.length > 200

        path.split('.').reduce(@facts) do |node, part|
          case node
          when Hash
            return false unless node.key?(part)

            node[part]
          when Array
            return false unless part.match?(/\A\d+\z/) && part.to_i < node.size

            node[part.to_i]
          else
            return false
          end
        end
        true
      end

      def drop(field, reason)
        @dropped << { field: field, reason: reason }
        nil
      end
    end
  end
end
