import { defineConfig } from 'vite';

export default defineConfig({
  root: 'src',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      // Forward /api/* to the Go backend during development so the browser
      // sees a single origin and there are no CORS issues.
      '/api': { target: 'http://localhost:8080' },
    },
  },
  test: {
    // Vitest config: run tests against a browser-like environment using jsdom.
    environment: 'jsdom',
    globals: true,
    include: ['**/*.test.ts'],
  },
});
