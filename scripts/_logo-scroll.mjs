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

// chip 区域的实际 scrollLeft 范围
const chipInfo = await page.evaluate(() => {
  const row = document.querySelector('.no-scrollbar')
  return row ? { scrollWidth: row.scrollWidth, clientWidth: row.clientWidth, children: row.children.length } : null
})
console.log('chips row:', chipInfo)

// 滚动到显示完所有 chips 的位置，截全宽图
await page.setViewport({ width: 980, height: 300, deviceScaleFactor: 2 })
await page.reload({ waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1200))
const chipY = await page.evaluate(() => {
  const el = document.querySelector('.chip')
  return el ? el.getBoundingClientRect().top : 0
})
await page.screenshot({ path: 'shots/v3/logos-wide.png', clip: { x: 0, y: Math.max(0, chipY - 8), width: 980, height: 80 } })
await browser.close()
console.log('done')
