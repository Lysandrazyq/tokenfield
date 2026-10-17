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
await mkdir('shots/v3', { recursive: true })

// 深色 - 首页
await page.evaluate(() => localStorage.setItem('tkf-appearance', JSON.stringify({ theme: 'dark', refraction: true })))
await page.goto('http://localhost:5173/#/', { waitUntil: 'networkidle0' })
await page.reload({ waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1500))
await page.screenshot({ path: 'shots/v3/final-dark-home.png' })

// 深色 - 编辑（Logo 芯片行）
await page.goto('http://localhost:5173/#/account/new', { waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1000))
await page.screenshot({ path: 'shots/v3/final-dark-edit.png' })

// 浅色 - 设置（免责声明）
await page.evaluate(() => localStorage.setItem('tkf-appearance', JSON.stringify({ theme: 'light', refraction: true })))
await page.goto('http://localhost:5173/#/settings', { waitUntil: 'networkidle0' })
await page.reload({ waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1000))
await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight))
await new Promise(r => setTimeout(r, 300))
await page.screenshot({ path: 'shots/v3/final-light-disclaimer.png' })

await browser.close()
console.log('done')
