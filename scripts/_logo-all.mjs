// 截图 Edit 页，滚动到 provider 选择器位置查看所有 logo
import puppeteer from 'puppeteer-core'
import { seed } from './seed.mjs'
import { mkdir } from 'node:fs/promises'

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader'],
})
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle0' })
await seed(page)
await page.goto('http://localhost:5173/#/account/new', { waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1200))
await mkdir('shots/v3', { recursive: true })

// 找 provider 选择 chip 区域截图
const chipArea = await page.evaluate(() => {
  const chips = document.querySelectorAll('.chip')
  if (!chips.length) return null
  const first = chips[0].getBoundingClientRect()
  const last = chips[chips.length - 1].getBoundingClientRect()
  return { x: first.left - 16, y: first.top - 12, width: 390 - (first.left - 16) * 2 + 32, height: last.bottom - first.top + 24 }
})
console.log('chipArea', chipArea)
if (chipArea) {
  await page.screenshot({ path: 'shots/v3/logos-chips.png', clip: chipArea })
}

// 全页
await page.screenshot({ path: 'shots/v3/logos-edit-full.png' })

// 检查加载的 logo 图片
const imgs = await page.evaluate(() =>
  [...document.querySelectorAll('[aria-hidden] img')].map(i => ({
    src: i.src.split('/').at(-1), w: i.naturalWidth, h: i.naturalHeight, display: i.style.display
  }))
)
console.log('imgs on edit page:', imgs)

await browser.close()
