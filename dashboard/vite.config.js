import { defineConfig } from 'vite'
import solid from 'vite-plugin-solid'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [solid(), tailwindcss()],
  server: {
    port: 5181,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:3011',
        changeOrigin: true,
        configure: (proxy) => {
          proxy.on('error', (err, _req, res) => {
            if (res && !res.headersSent && res.writeHead) {
              res.writeHead(502, { 'Content-Type': 'application/json' })
              res.end(JSON.stringify({ error: 'backend_unavailable', message: err.message }))
            }
          })
        }
      },
      '/cable': {
        target: 'ws://127.0.0.1:3011',
        ws: true,
        changeOrigin: true,
        secure: false,
        configure: (proxy) => {
          proxy.on('error', () => {
            // Cable client auto-reconnects on socket drop
          })
        }
      }
    }
  }
})
