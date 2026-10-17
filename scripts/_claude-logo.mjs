// Claude 官网的 favicon 是 SVG inline，通过截图 canvas 拿
import puppeteer from 'puppeteer-core'
import { writeFileSync } from 'node:fs'

const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true })
const page = await browser.newPage()
await page.setViewport({ width: 200, height: 200 })
await page.setContent(`<html><body style="margin:0;background:transparent">
  <img src="https://assets.claude.com/95a868946ac8a31e5ff832e2899f294aa368b836.png" style="width:192px;height:192px" />
</body></html>`)
await page.waitForSelector('img')
await new Promise(r => setTimeout(r, 2000))
const buf = await page.screenshot({ type: 'png', clip: { x: 0, y: 0, width: 192, height: 192 } })
writeFileSync('public/logos/claude.png', buf)
console.log('claude', buf.length)
await browser.close()
