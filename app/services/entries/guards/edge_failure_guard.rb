# frozen_string_literal: true

module Entries
  module Guards
    class EdgeFailureGuard
      class << self
        def call(context)
          edge_check = Live::EdgeFailureDetector.instance.entries_paused?(index_key: context[:index_cfg][:key])
          return EntryGuardPipeline::PASS unless edge_check[:paused]

          resume_str = edge_check[:resume_at]&.strftime('%H:%M IST') || 'manual override'
          { blocked: "edge failure: #{edge_check[:reason]} (resume at: #{resume_str})" }
        end
      end
    end
  end
end
