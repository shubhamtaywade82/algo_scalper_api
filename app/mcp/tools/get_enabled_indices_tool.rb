# frozen_string_literal: true

class GetEnabledIndicesTool < ApplicationMCPTool
  tool_name 'get_enabled_indices'
  description 'Configured tradable indices with their segment and security id. Read-only.'

  def perform
    rows = IndexConfigLoader.load_indices.map do |i|
      {
        index_key: i[:key],
        symbol: i[:symbol],
        segment: i[:segment],
        security_id: i[:sid]
      }
    end

    render_json(count: rows.size, indices: rows)
  end
end
