import { createConsumer } from '@rails/actioncable'

// Prefer env override when provided.
// Otherwise, use the dashboard origin so Vite's dev proxy can route `/cable`
// to the Rails ActionCable endpoint (Rails runs on 3001 in this repo).
// This also avoids hardcoding ports that may differ per machine.
const url =
  import.meta.env.VITE_CABLE_URL ||
  (typeof window !== 'undefined'
    ? `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/cable`
    : 'ws://127.0.0.1:3001/cable')

export default createConsumer(url)
