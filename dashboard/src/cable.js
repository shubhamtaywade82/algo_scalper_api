import { createConsumer } from '@rails/actioncable'

// Prefer env override when provided.
// Otherwise, use the dashboard origin so Vite's dev proxy can route `/cable`
// to the Rails ActionCable endpoint (Rails runs on 3011 in this repo).
// This also avoids hardcoding ports that may differ per machine.
const baseUrl =
  import.meta.env.VITE_CABLE_URL ||
  (typeof window !== 'undefined'
    ? `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/cable`
    : 'ws://127.0.0.1:3011/cable')

// Browsers can't set headers on a WebSocket handshake, so ApplicationCable::Connection
// reads the dashboard token from ?token=. Without it every live push is rejected
// whenever API_DASHBOARD_TOKEN is set (always in production).
function withToken(url) {
  const token = import.meta.env.VITE_API_DASHBOARD_TOKEN
  if (!token) return url
  return `${url}${url.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`
}

export default createConsumer(withToken(baseUrl))
