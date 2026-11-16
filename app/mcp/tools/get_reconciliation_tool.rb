# frozen_string_literal: true

class GetReconciliationTool < ApplicationMCPTool
  tool_name 'get_reconciliation'
  description 'Latest broker reconciliation run for the active mode and its unresolved discrepancies. Read-only.'

  def perform
    snapshot = market_snapshot
    run = ReconciliationRun.recent.find_by(mode: snapshot['mode'])

    render_json(
      generated_at: snapshot['generated_at'],
      run: run && run_row(run),
      unresolved_discrepancies: run ? unresolved_rows(run) : []
    )
  end

  private

  def run_row(run)
    {
      id: run.id,
      status: run.status,
      mode: run.mode,
      started_at: run.started_at&.iso8601,
      completed_at: run.completed_at&.iso8601,
      duration_seconds: run.duration_seconds,
      halted_trading: run.halted_trading == true,
      discrepancies_found: run.discrepancies_found
    }
  end

  def unresolved_rows(run)
    run.discrepancies.unresolved.limit(20).map do |d|
      {
        id: d.id,
        entity_type: d.entity_type,
        field_name: d.field_name,
        severity: d.severity,
        resolution: d.resolution
      }
    end
  end
end
