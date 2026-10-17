// 检查各图标尺寸和格式
import puppeteer from 'puppeteer-core'
import { readdirSync } from 'node:fs'

const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true })
const page = await browser.newPage()
await page.setContent(`<html><body></body></html>`)

const files = readdirSync('public/logos').filter(f => !f.startsWith('_'))
for (const f of files) {
  const info = await page.evaluate(async (src) => {
    return new Promise(r => {
      const img = new Image()
      img.onload = () => r({ w: img.naturalWidth, h: img.naturalHeight, ok: true })
      img.onerror = () => r({ ok: false })
      img.src = 'http://localhost:5173/logos/' + src
    })
  }, f)
  console.log(f.padEnd(20), info.ok ? `${info.w}×${info.h}` : 'FAIL')
}
await browser.close()
