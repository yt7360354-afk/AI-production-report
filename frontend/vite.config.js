import { defineConfig } from 'vite'

// 리포트 화면 개발 서버: http://127.0.0.1:5174
// /api 요청은 Spring Boot 백엔드(8080)로 전달한다.
export default defineConfig({
  server: {
    host: '127.0.0.1',
    port: 5174,
    strictPort: true,
    proxy: {
      '/api': 'http://localhost:8080',
    },
  },
})
