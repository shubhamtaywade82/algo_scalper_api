import { createSignal, onCleanup, createEffect } from 'solid-js'
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

  function subscribeToIndex(key) {
    subscription?.unsubscribe()
    clearTimeout(staleTimer)
    setChain(null)
    setIsStale(true)

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
