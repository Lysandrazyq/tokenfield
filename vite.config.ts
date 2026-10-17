import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  // 预览工具会通过 PORT 分配端口；手动跑 npm run dev 时仍是 5173
  server: { port: Number(process.env.PORT) || 5173 },
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: '额度终端 TOKENFIELD',
        short_name: '额度终端',
        description: '统一管理你的 AI 订阅、中转站余额和额度重置',
        lang: 'zh-CN',
        theme_color: '#05060c',
        background_color: '#05060c',
        display: 'standalone',
        icons: [{ src: 'icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' }],
      },
    }),
  ],
})
