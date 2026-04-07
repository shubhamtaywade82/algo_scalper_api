import { createConsumer } from '@rails/actioncable'

// Use a relative path by default to let the browser/proxy handle the protocol and host.
// This is much more reliable for Vite/Nginx proxying.
const url = import.meta.env.VITE_CABLE_URL || '/cable'

console.log(`[Cable] Initializing connection to: ${url}`)

const consumer = createConsumer(url)

// Add global connection logging to help debug
const originalSend = consumer.send
consumer.send = (data) => {
  console.log('[Cable] Sending:', data)
  return originalSend.call(consumer, data)
}

export default consumer
