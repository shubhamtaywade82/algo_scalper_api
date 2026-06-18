/**
 * Maps closed-position exit metadata to a short dashboard label.
 * Prefer exit_path / exit_reason over PnL-based TP/SL guessing.
 */
export function exitBadge(pos) {
  const reason = String(pos.exit_reason || '').toLowerCase()
  const path = String(pos.exit_path || '').toLowerCase()
  const combined = `${reason} ${path}`
  const pnl = Number(pos.pnl ?? pos.last_pnl_rupees ?? 0)

  if (combined.includes('dte_zero') || combined.includes('theta_flat')) {
    return {
      label: 'THETA',
      cls: pnl >= 0 ? 'text-amber-400 border-amber-500/30' : 'text-orange-400 border-orange-500/30',
    }
  }

  if (combined.includes('profit_floor_time_kill')) {
    return { label: 'FLR-T', cls: 'text-amber-400 border-amber-500/30' }
  }

  if (combined.includes('profit_floor')) {
    return {
      label: pnl < 0 ? 'FLR−' : 'FLR',
      cls: pnl < 0 ? 'text-orange-400 border-orange-500/30' : 'text-cyan-400 border-cyan-500/30',
    }
  }

  if (combined.includes('premium_momentum')) {
    return { label: 'PMF', cls: 'text-amber-400 border-amber-500/30' }
  }

  if (combined.includes('stop_loss') || combined.includes('premium_r_stop')) {
    return { label: 'SL', cls: 'text-red-400 border-red-500/30' }
  }

  if (combined.includes('structure')) {
    return { label: 'STRUCT', cls: 'text-orange-400 border-orange-500/30' }
  }

  if (combined.includes('time_stop') || combined.includes('time_based') || combined.includes('eod_force')) {
    return { label: 'TIME', cls: 'text-yellow-400 border-yellow-500/30' }
  }

  if (combined.includes('trail')) {
    return { label: 'TRAIL', cls: 'text-blue-400 border-blue-500/30' }
  }

  if (combined.includes('take_profit') || combined.includes('percentage_pnl_exit') || combined.includes('rr_profit')) {
    return { label: 'TP', cls: 'text-emerald-400 border-emerald-500/30' }
  }

  if (combined.includes('manual')) {
    return { label: 'MNL', cls: 'text-purple-400 border-purple-500/30' }
  }

  if (combined.includes('vix_force')) {
    return { label: 'VIX', cls: 'text-rose-400 border-rose-500/30' }
  }

  const classification = pos.exit_classification
  if (classification === 'profit') {
    return { label: 'WIN', cls: 'text-emerald-400 border-emerald-500/30' }
  }
  if (classification === 'loss') {
    return { label: 'LOSS', cls: 'text-red-400 border-red-500/30' }
  }
  if (classification === 'breakeven') {
    return { label: 'BE', cls: 'text-yellow-400 border-yellow-500/30' }
  }

  if (!pos.exit_reason && !pos.exit_path) {
    return { label: '—', cls: 'text-gray-600 border-gray-700' }
  }

  const token = (path || reason).replace(/[^a-z0-9_]/g, '_').split('_').find((t) => t.length > 2)
  return {
    label: (token || 'EXIT').slice(0, 8).toUpperCase(),
    cls: 'text-gray-400 border-gray-700',
  }
}
