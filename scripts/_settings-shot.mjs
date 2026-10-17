import puppeteer from 'puppeteer-core'
import { seed } from './seed.mjs'
import { mkdir } from 'node:fs/promises'

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle0' })
await seed(page)
// 设置页截图，滚到免责声明
await page.goto('http://localhost:5173/#/settings', { waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1200))
// 滚到底部看免责声明
await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight))
await new Promise(r => setTimeout(r, 400))
await mkdir('shots/v3', { recursive: true })
await page.screenshot({ path: 'shots/v3/settings-disclaimer.png' })
// 滚回顶部看设置整体
await page.evaluate(() => window.scrollTo(0, 0))
await new Promise(r => setTimeout(r, 400))
await page.screenshot({ path: 'shots/v3/settings-top.png' })
await browser.close()
console.log('done')
