import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { HashRouter } from 'react-router-dom'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'
import App from './App'
import { preload } from './lib/store'
import './index.css'

dayjs.locale('zh-cn')

// 先把本地数据读进内存再渲染，首屏和每次切页都不会有空帧
preload().then(() =>
  createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <HashRouter>
      <App />
    </HashRouter>
  </StrictMode>,
  ),
)
