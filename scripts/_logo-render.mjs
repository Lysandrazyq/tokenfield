// 简单截图验证
import puppeteer from 'puppeteer-core'
import { seed } from './seed.mjs'
import { mkdir, writeFile } from 'node:fs/promises'

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const page = await browser.newPage()
await page.setViewport({ width: 1200, height: 200, deviceScaleFactor: 2 })
// 直接在空白页渲染所有 logo
await page.setContent(`<!doctype html>
<html><head><style>
  body { margin: 20px; background: #0a0b10; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
  img { width: 56px; height: 56px; border-radius: 16px; object-fit: cover; }
  span { color: #fff; font-size: 11px; font-family: sans-serif; display: flex; flex-direction: column; align-items: center; gap: 4px; }
</style></head><body>
${['chatgpt','claude','gemini','deepseek','kimi','glm','qwen','doubao','minimax'].map(k =>
  `<span><img src="http://localhost:5173/logos/${k}.${k==='qwen'?'svg':'png'}" alt="${k}" />${k}</span>`
).join('')}
</body></html>`)
await new Promise(r => setTimeout(r, 2000))
const buf = await page.screenshot({ type: 'png' })
await mkdir('shots/v3', { recursive: true })
await writeFile('shots/v3/logos-all.png', buf)
console.log('saved', buf.length)
await browser.close()
