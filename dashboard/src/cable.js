import { createConsumer } from '@rails/actioncable'

// Connect directly to Rails — bypasses the Vite dev server WebSocket proxy,
// which conflicts with Vite's own HMR WebSocket on the same port (5173).
// VITE_CABLE_URL can override in .env.local if the Rails port changes.
const url = import.meta.env.VITE_CABLE_URL || 'ws://localhost:3001/cable'

export default createConsumer(url)
