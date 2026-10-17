import puppeteer from 'puppeteer-core'
import { seed } from './seed.mjs'

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader'],
})
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
page.on('pageerror', e => console.log('ERR', e.message))

await page.goto('http://localhost:5173/', { waitUntil: 'networkidle0' })
await seed(page)
await page.goto('http://localhost:5173/#/', { waitUntil: 'networkidle0' })
await page.reload({ waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 1500))

// 检查徽标是否渲染成图片而不是文字
const info = await page.evaluate(() => {
  const imgs = [...document.querySelectorAll('[aria-hidden] img')]
  return imgs.map(img => ({
    src: img.src.split('/').at(-1),
    w: img.naturalWidth, h: img.naturalHeight,
    visible: img.style.display !== 'none',
  }))
})
console.log('logos found:', info.length, JSON.stringify(info, null, 2))

const { mkdir } = await import('node:fs/promises')
await mkdir('shots/v3', { recursive: true })
await page.screenshot({ path: 'shots/v3/logos-home.png' })

// 账号列表页
await page.goto('http://localhost:5173/#/account/new', { waitUntil: 'networkidle0' })
await new Promise(r => setTimeout(r, 600))
await page.screenshot({ path: 'shots/v3/logos-edit.png' })

await browser.close()
console.log('done')
