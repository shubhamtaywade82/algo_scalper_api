import { createSignal, onCleanup, createEffect } from 'solid-js'
import { apiClient } from '../lib/api'
import cable from '../cable'

const STALE_AFTER_MS = 5000

export function useOptionChain(indexKey) {
  const [chain, setChain] = createSignal(null)
  const [connected, setConnected] = createSignal(false)
  const [isStale, setIsStale] = createSignal(true)

  let subscription = null
  let staleTimer = null

  function markFresh() {
    setIsStale(false)
    clearTimeout(staleTimer)
    staleTimer = setTimeout(() => setIsStale(true), STALE_AFTER_MS)
  }

  async function fetchOptionChainRest(key) {
    try {
      const res = await apiClient.get(`/option_chain/${key}`)
      if (res.data && res.data.legs && res.data.legs.length > 0) {
        // Only update with REST data if ActionCable has not already received data for this key
        const current = chain()
        if (!current || current.index_key !== key) {
          setChain(res.data)
          setIsStale(res.data.chain_stale)
        }
      }
    } catch (err) {
      console.warn('[useOptionChain] Failed to fetch REST option chain:', err)
    }
  }

  function subscribeToIndex(key) {
    subscription?.unsubscribe()
    clearTimeout(staleTimer)
    setChain(null)
    setIsStale(true)

    // Trigger REST fallback load in parallel
    fetchOptionChainRest(key)

    subscription = cable.subscriptions.create(
      { channel: 'OptionChainChannel', index_key: key },
      {
        connected() {
          setConnected(true)
          markFresh()
        },
        disconnected() {
          setConnected(false)
        },
        received(data) {
          markFresh()
          setChain(data)
        }
      }
    )
  }

  createEffect(() => {
    const key = typeof indexKey === 'function' ? indexKey() : indexKey
    if (key) subscribeToIndex(key)
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearTimeout(staleTimer)
  })

  return { chain, connected, isStale }
}
