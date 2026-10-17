import puppeteer from 'puppeteer-core'
import { writeFileSync } from 'node:fs'
const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true })
const page = await browser.newPage()
await page.setViewport({ width: 192, height: 192 })
await page.setContent(`<html><body style="margin:0;background:transparent">
  <img src="https://www.minimaxi.com/favicon.ico" style="width:192px;height:192px;image-rendering:pixelated" />
</body></html>`)
await page.waitForSelector('img')
await new Promise(r => setTimeout(r, 2000))
const buf = await page.screenshot({ type: 'png', clip: { x: 0, y: 0, width: 192, height: 192 } })
writeFileSync('public/logos/minimax.png', buf)
console.log('minimax', buf.length)
await browser.close()
