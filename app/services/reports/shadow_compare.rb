# frozen_string_literal: true

module Reports
  # Sets one day's paper trades of this app beside the options-trading-agent's paper journal, so the two can be
  # judged on the same market before they are coupled any further. Read-only: it never touches orders or either system.
  class ShadowCompare
    MATCH_WINDOW = 10.minutes
    DIRECTION_BY_OPTION_TYPE = { 'CE' => :bullish, 'PE' => :bearish }.freeze
    Trade = Struct.new(:source, :index_key, :direction, :entered_at, :pnl, keyword_init: true)

    def initialize(date:, journal_dir:)
      @date = date
      @journal_path = Pathname.new(journal_dir).join("events-#{date.iso8601}.jsonl")
    end

    # @return [Hash] matched pairs, trades only one side took, per-side totals, and :agent_journal (:found/:missing)
    def call
      rails = rails_trades
      agent = agent_trades
      matched, rails_only, agent_only = pair_up(rails, agent)
      {
        matched: matched, rails_only: rails_only, agent_only: agent_only,
        totals: { rails: totals(rails), agent: totals(agent) },
        agent_journal: @journal_path.exist? ? :found : :missing
      }
    end

    # @return [String] the comparison as a plain-text report for the terminal
    def self.render(date, result)
      totals = result[:totals]
      lines = ["Shadow compare #{date.iso8601} (agent journal: #{result[:agent_journal]})",
               format('Rails  %<trades>3d trades  %<pnl>+10.2f', totals[:rails]),
               format('Agent  %<trades>3d trades  %<pnl>+10.2f', totals[:agent]),
               "Matched (same index and direction within #{MATCH_WINDOW.inspect}): #{result[:matched].size}"]
      lines += result[:matched].map { |pair| "  #{pair.map { |t| describe(t) }.join('  |  ')}" }
      lines += ['Rails only:'] + result[:rails_only].map { |t| "  #{describe(t)}" }
      lines += ['Agent only:'] + result[:agent_only].map { |t| "  #{describe(t)}" }
      lines.join("\n")
    end

    def self.describe(trade)
      format('%<src>-5s %<idx>s %<dir>s %<at>s %<pnl>+.0f', src: trade.source, idx: trade.index_key,
                                                            dir: trade.direction, at: trade.entered_at.strftime('%H:%M'), pnl: trade.pnl)
    end

    private

    def rails_trades
      day = @date.in_time_zone.all_day
      PositionTracker.paper.where(created_at: day).order(:created_at).map do |tracker|
        Trade.new(source: :rails, index_key: tracker.index_key, direction: direction_of(tracker.symbol, tracker.side),
                  entered_at: tracker.created_at, pnl: tracker.last_pnl_rupees.to_f)
      end
    end

    def direction_of(symbol, side)
      return :bearish if symbol.to_s.end_with?('PE') || side.to_s.end_with?('pe')

      :bullish
    end

    def agent_trades
      return [] unless @journal_path.exist?

      events = journal_events
      fills = events.select { |e| e['type'] == 'entry_filled' }.index_by { |e| e['correlationId'] }
      events.select { |e| e['type'] == 'trade_closed' }.filter_map do |closed|
        agent_trade(closed, fills[closed['positionId']])
      end
    end

    def agent_trade(closed, fill)
      return unless fill

      Trade.new(source: :agent, index_key: closed['underlying'], direction: DIRECTION_BY_OPTION_TYPE[closed['optionType']],
                entered_at: Time.zone.parse(fill['ts']), pnl: closed['pnlInr'].to_f)
    end

    # A live run can share the journal directory; only paper events belong in a paper comparison.
    def journal_events
      events = @journal_path.each_line.filter_map { |line| parse_event(line) }
      events.select { |event| event['mode'] == 'paper' }
    end

    # The agent appends while running, so the last line can be half-written.
    def parse_event(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    def pair_up(rails, agent)
      remaining = agent.dup
      matched = []
      rails_only = rails.reject do |trade|
        partner = remaining.find { |candidate| same_call?(trade, candidate) }
        remaining.delete(partner) && (matched << [trade, partner]) if partner
        partner
      end
      [matched, rails_only, remaining]
    end

    def same_call?(left, right)
      left.index_key == right.index_key && left.direction == right.direction &&
        (left.entered_at - right.entered_at).abs <= MATCH_WINDOW
    end

    def totals(trades)
      { trades: trades.size, pnl: trades.sum(&:pnl).round(2) }
    end
  end
end
