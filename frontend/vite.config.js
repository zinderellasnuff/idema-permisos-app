import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// En desarrollo, /api se redirige al backend Python (server.py).
export default defineConfig({
  plugins: [react()],
  server: { proxy: { '/api': 'http://127.0.0.1:8080' } },
})
