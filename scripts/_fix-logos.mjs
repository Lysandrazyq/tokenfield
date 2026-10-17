// 用 Puppeteer 截图到 canvas 再 toDataURL，把低分辨率 PNG 重新渲染成 96×96
import puppeteer from 'puppeteer-core'
import { writeFileSync } from 'node:fs'

const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true })

// claude.png (32px) → 去官网找更大的
const fixes = [
  { key: 'claude',   src: 'https://assets.claude.com/95a868946ac8a31e5ff832e2899f294aa368b836.png?w=192&h=192' },
  { key: 'minimax',  src: 'https://static.minimaxi.com/static/minimaxi/favicon192.png' },
]

for (const { key, src } of fixes) {
  const page = await browser.newPage()
  try {
    await page.goto(src, { timeout: 20000 })
    const buf = await page.evaluate(async (url) => {
      const resp = await fetch(url)
      const ab = await resp.arrayBuffer()
      return Array.from(new Uint8Array(ab))
    }, src)
    writeFileSync(`public/logos/${key}.png`, Buffer.from(buf))
    console.log(key, buf.length, 'bytes')
  } catch (e) {
    console.log(key, 'fail', e.message.slice(0, 60))
  }
  await page.close()
}
await browser.close()
