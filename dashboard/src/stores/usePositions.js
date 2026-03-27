import { createSignal, onMount, onCleanup } from 'solid-js'
import cable from '../cable'

const WS_STALE_AFTER_MS = 3000
const BACKFILL_INTERVAL_MS = 5000

export function usePositions() {
  const [open, setOpen] = createSignal([])
  const [closed, setClosed] = createSignal([])
  const [connected, setConnected] = createSignal(false)
  const [isStale, setIsStale] = createSignal(true)
  const [lastMessageAt, setLastMessageAt] = createSignal(null)

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
      const res = await fetch('/api/positions')
      const data = await res.json()
      setOpen(data.open || [])
      setClosed(data.closed || [])
    } catch (e) {
      console.error('[Positions] fetch failed:', e)
    }
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

    subscription = cable.subscriptions.create('PositionsChannel', {
      connected() {
        console.log('✅ [WS:Positions] Connected')
        setConnected(true)
        markFresh()
      },
      received(data) {
        // ANY incoming data marks fresh and applies update instantly
        console.debug('⚡ [WS:Positions] Update:', data)
        markFresh()
        if (data.type === 'pnl_stale') {
          applyPnlStale(data)
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

  return { open, closed, connected, isStale, lastMessageAt, fetchPositions }
}
