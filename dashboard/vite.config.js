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
        changeOrigin: true
      },
      '/cable': {
        target: 'http://127.0.0.1:3011',
        ws: true,
        changeOrigin: true,
        secure: false
      }
    }
  }
})
