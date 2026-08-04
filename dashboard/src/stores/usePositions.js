import { createSignal, onMount, onCleanup } from 'solid-js'
import toast from 'solid-toast'
import cable from '../cable'
import { dashboardApiHeaders } from '../lib/dashboardApi'

// Aligned with backend Live::FeedHealthService ticks threshold (10s) — illiquid strikes
// can go several seconds between prints without the feed actually being down.
const WS_STALE_AFTER_MS = 9000
const BACKFILL_INTERVAL_MS = 5000

export function usePositions() {
  const [open, setOpen] = createSignal([])
  const [closed, setClosed] = createSignal([])
  const [connected, setConnected] = createSignal(false)
  const [isStale, setIsStale] = createSignal(true)
  const [lastMessageAt, setLastMessageAt] = createSignal(null)
  const [closingPositionId, setClosingPositionId] = createSignal(null)

  let subscription = null
  let staleTimer = null
  let backfillTimer = null

  function markFresh() {
    setIsStale(false)
    setLastMessageAt(new Date().toISOString())
    clearTimeout(staleTimer)
    staleTimer = setTimeout(() => setIsStale(true), WS_STALE_AFTER_MS)
  }

  function clearStaleTimer() {
    clearTimeout(staleTimer)
  }

  function stopBackfill() {
    clearInterval(backfillTimer)
  }

  function applyPnlStale(data) {
    if (!data?.id) return
    setOpen(prev => {
      const idx = prev.findIndex(p => Number(p.id) === Number(data.id))
      if (idx === -1) return prev
      const next = [...prev]
      next[idx] = { ...next[idx], ltp_stale: true }
      return next
    })
  }

  async function fetchPositions() {
    try {
      const res = await fetch('/api/positions', { headers: dashboardApiHeaders() })
      const data = await res.json()
      // Merge server data with any live WS fields already applied (ltp, pnl, ltp_stale).
      // This prevents the periodic poll from overwriting fresher WS values.
      setOpen(prev => {
        const prevById = Object.fromEntries(prev.map(p => [p.id, p]))
        return (data.open || []).map(serverPos => {
          const live = prevById[serverPos.id]
          if (!live) return serverPos
          // Server data wins for stable fields; keep live WS fields if they are fresher
          return { ...serverPos, ...pickLiveFields(live) }
        })
      })
      setClosed(data.closed || [])
    } catch (e) {
      console.error('[Positions] fetch failed:', e)
    }
  }

  async function closeOpenPosition(positionId) {
    const id = positionId
    if (id == null) return { ok: false }

    setClosingPositionId(id)
    try {
      const res = await fetch(`/api/positions/${id}/close`, {
        method: 'POST',
        headers: {
          ...dashboardApiHeaders(),
          Accept: 'application/json'
        }
      })
      let data = {}
      try {
        data = await res.json()
      } catch {
        /* ignore */
      }

      if (!res.ok) {
        const msg =
          data.error === 'not_found'
            ? 'Position not found or already closed'
            : data.message || data.error || `Close failed (${res.status})`
        toast.error(msg)
        return { ok: false, status: res.status, data }
      }

      if (data.reason === 'exit_already_requested') {
        toast.success('Exit already in progress for this position')
      } else if (data.reason === 'already_exited') {
        toast.success('Position was already closed')
      } else {
        toast.success('Exit order submitted')
      }
      await fetchPositions()
      return { ok: true, data }
    } catch (e) {
      console.error('[Positions] close failed:', e)
      toast.error('Could not reach server to close position')
      return { ok: false }
    } finally {
      setClosingPositionId(null)
    }
  }

  // Only carry forward the real-time fields that WS updates provide.
  // Everything else is authoritative from the server.
  function pickLiveFields(pos) {
    const live = {}
    if (pos.ltp != null)       live.ltp       = pos.ltp
    if (pos.pnl != null)       live.pnl       = pos.pnl
    if (pos.pnl_pct != null)   live.pnl_pct   = pos.pnl_pct
    if (pos.hwm_pnl != null)   live.hwm_pnl   = pos.hwm_pnl
    if (pos.ltp_stale != null) live.ltp_stale = pos.ltp_stale
    if (pos.sl_price != null)  live.sl_price  = pos.sl_price
    if (pos.tp_price != null)  live.tp_price  = pos.tp_price
    return live
  }

  function applyPnlUpdate(update) {
    if (!update) return
    setOpen(prev => {
      // Robust matching: ID first, then Symbol fallback
      const idx = prev.findIndex(p => 
        (update.id && Number(p.id) === Number(update.id)) || 
        (update.symbol && p.symbol === update.symbol)
      )
      if (idx === -1) return prev
      const next = [...prev]
      next[idx] = { ...next[idx], ...update }
      return next
    })
  }

  onMount(() => {
    fetchPositions()

    // Periodic backfill: catches new positions opened, exited, or any WS gaps.
    backfillTimer = setInterval(() => fetchPositions(), BACKFILL_INTERVAL_MS)

    subscription = cable.subscriptions.create('PositionsChannel', {
      connected() {
        console.log('✅ [WS:Positions] Connected')
        setConnected(true)
        markFresh()
        fetchPositions() // sync on reconnect
      },
      received(data) {
        // ANY incoming data marks fresh and applies update instantly
        console.debug('⚡ [WS:Positions] Update:', data)
        markFresh()
        if (data.type === 'pnl_stale') {
          applyPnlStale(data)
        } else if (data.type === 'keepalive') {
          // markFresh() above resets WS stale timer
        } else if (data.type === 'position_exited') {
          setOpen(prev => prev.filter(p => Number(p.id) !== Number(data.id)))
        } else {
          applyPnlUpdate(data)
        }
      }
    })
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearStaleTimer()
    stopBackfill()
  })

  return {
    open,
    closed,
    connected,
    isStale,
    lastMessageAt,
    fetchPositions,
    closeOpenPosition,
    closingPositionId
  }
}
