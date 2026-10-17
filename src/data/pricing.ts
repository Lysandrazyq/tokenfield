import type { Billing, Currency, ResetKind } from '../db'

/**
 * 官方价格目录。
 *
 * 规则：
 *   - 每个数字都必须有 source（官网链接）和 checked（核对日期），只收录在官网上核对过的价格；
 *   - 核不到的不写，宁缺毋滥；
 *   - 价格经常变，界面上永远同时显示「核对于 YYYY-MM-DD」和官网链接，让用户自己点进去再确认。
 */

export interface Provider {
  key: string
  name: string
  color: string
  /** 是否有面向个人的会员订阅；DeepSeek 这类只有按量 API 的为 false */
  hasSubscription: boolean
  /** 新建时的默认计费方式 */
  defaultBilling: Billing
  currency: Currency
  /** 官方价格页 */
  pricingUrl?: string
  note?: string
}

export interface Plan {
  id: string
  provider: string
  name: string
  /** 月价 */
  price: number
  currency: Currency
  /** 官方写的用量限制，原文概括 */
  limits: string
  resetKind: ResetKind
  resetHours?: number
  /** 适合谁 */
  fit?: string
  /** 是否包含编程 Agent（Codex / Claude Code / Gemini CLI 等） */
  coding?: boolean
  /** 只能给编程工具用的套餐（不能拿来日常聊天） */
  codingOnly?: boolean
  source: string
  checked: string
}

export interface ApiModel {
  id: string
  provider: string
  name: string
  /** 每百万 token 价格 */
  input: number
  output: number
  cachedInput?: number
  currency: Currency
  tier: 'flagship' | 'balanced' | 'cheap'
  note?: string
  source: string
  checked: string
}

export const PROVIDERS: Provider[] = [
  { key: 'chatgpt', name: 'ChatGPT', color: '#10a37f', hasSubscription: true, defaultBilling: 'subscription', currency: 'USD' },
  { key: 'claude', name: 'Claude', color: '#d97757', hasSubscription: true, defaultBilling: 'subscription', currency: 'USD' },
  { key: 'gemini', name: 'Gemini', color: '#4285f4', hasSubscription: true, defaultBilling: 'subscription', currency: 'USD' },
  { key: 'deepseek', name: 'DeepSeek', color: '#4d6bfe', hasSubscription: false, defaultBilling: 'payg', currency: 'CNY', note: '网页和 App 免费，API 只有按量付费，没有会员。工作日 9–12 点、14–18 点以外半价' },
  { key: 'kimi', name: 'Kimi', color: '#3b4a6b', hasSubscription: true, defaultBilling: 'subscription', currency: 'CNY', note: 'Kimi 会员给 App 和 Kimi Code 用；API 是另一套，只有按量付费' },
  { key: 'glm', name: '智谱 GLM', color: '#3859ff', hasSubscription: true, defaultBilling: 'payg', currency: 'CNY', note: '会员是 GLM Coding Plan，给 Claude Code 等编程工具用' },
  { key: 'qwen', name: '通义千问', color: '#615ced', hasSubscription: true, defaultBilling: 'payg', currency: 'CNY', note: '阿里云百炼 Coding Plan 是编程套餐；千问 App 免费' },
  { key: 'doubao', name: '豆包', color: '#2d7ff9', hasSubscription: true, defaultBilling: 'payg', currency: 'CNY', note: '火山方舟 Coding Plan 是编程套餐；豆包 App 免费' },
  { key: 'minimax', name: 'MiniMax', color: '#e5484d', hasSubscription: true, defaultBilling: 'payg', currency: 'CNY', note: 'Token Plan 是包月额度，按 5 小时窗口和周窗口恢复' },
  { key: 'relay', name: '中转站', color: '#8e7cf0', hasSubscription: false, defaultBilling: 'balance', currency: 'CNY', note: '第三方转售，价格以站点为准' },
  { key: 'custom', name: '其他', color: '#8e8e93', hasSubscription: true, defaultBilling: 'subscription', currency: 'USD' },
]

/*
 * 2026-10-10 逐个打开官网核对（无头浏览器渲染后读页面文字）。
 * 每条后面的注释是官网原文摘录，方便下次核对时对照。
 */
const C = '2026-10-10'
const U = {
  chatgpt: 'https://chatgpt.com/pricing',
  claude: 'https://claude.com/pricing',
  gemini: 'https://gemini.google/subscriptions/',
  kimi: 'https://www.kimi.com/membership/pricing',
  glm: 'https://bigmodel.cn/glm-coding',
  qwen: 'https://help.aliyun.com/zh/model-studio/coding-plan',
  doubao: 'https://www.volcengine.com/docs/82379/1544106',
  minimax: 'https://platform.minimaxi.com/docs/guides/pricing-token-plan',
}

export const PLANS: Plan[] = [
  // "Go $8 / month" · "Plus $20 / month" · "Pro From $100 / month — Your choice of 3 usage tiers"
  { id: 'chatgpt-go', provider: 'chatgpt', name: 'Go', price: 8, currency: 'USD', limits: '文本对话不限量，上传 / 生图比免费版多，可能有广告', resetKind: 'none', coding: true, fit: '只想多聊几句', source: U.chatgpt, checked: C },
  { id: 'chatgpt-plus', provider: 'chatgpt', name: 'Plus', price: 20, currency: 'USD', limits: '高级推理模型有限额，Codex 用量更高', resetKind: 'none', coding: true, fit: '主力日常使用', source: U.chatgpt, checked: C },
  { id: 'chatgpt-pro', provider: 'chatgpt', name: 'Pro', price: 100, currency: 'USD', limits: '$100 起，三档用量可选，Codex 会话更长', resetKind: 'none', coding: true, fit: '重度 / 专业推理', source: U.chatgpt, checked: C },
  // "$20 if billed monthly" · "Max From $100" · "5x or 20x the usage of Pro per 5-hour session" · "a five-hour session limit and a weekly limit"
  { id: 'claude-pro', provider: 'claude', name: 'Pro', price: 20, currency: 'USD', limits: '每 5 小时一个用量窗口 + 每周上限，含 Claude Code', resetKind: 'hours', resetHours: 5, coding: true, fit: '写作、编程主力', source: U.claude, checked: C },
  { id: 'claude-max5', provider: 'claude', name: 'Max 5x', price: 100, currency: 'USD', limits: '每 5 小时用量为 Pro 的 5 倍 + 每周上限，每月送 $100 API 额度', resetKind: 'hours', resetHours: 5, coding: true, fit: '每天大量用 Claude Code', source: U.claude, checked: C },
  { id: 'claude-max20', provider: 'claude', name: 'Max 20x', price: 200, currency: 'USD', limits: '每 5 小时用量为 Pro 的 20 倍 + 每周上限，每月送 $200 API 额度', resetKind: 'hours', resetHours: 5, coding: true, fit: '全天候 Agent', source: U.claude, checked: C },
  // "Google AI Plus $4.99/ month" · "Google AI Pro $19.99/ month" · "Ultra $99.99: 5x … $199.99: 20x higher usage limits vs. AI Pro"
  { id: 'gemini-plus', provider: 'gemini', name: 'AI Plus', price: 4.99, currency: 'USD', limits: '用量为免费版 2 倍，可用 3.1 Pro', resetKind: 'none', fit: '轻度使用', source: U.gemini, checked: C },
  { id: 'gemini-pro', provider: 'gemini', name: 'AI Pro', price: 19.99, currency: 'USD', limits: '用量为免费版 4 倍，含 Jules 编程 Agent', resetKind: 'none', coding: true, fit: '日常主力', source: U.gemini, checked: C },
  { id: 'gemini-ultra', provider: 'gemini', name: 'AI Ultra', price: 99.99, currency: 'USD', limits: '用量为 AI Pro 的 5 倍（$199.99 档为 20 倍），含 Deep Think', resetKind: 'none', coding: true, fit: '重度使用', source: U.gemini, checked: C },
  // 连续包月价："Go ¥49" · "Plus ¥99 — Kimi Code available" · "Pro ¥199"（年付分别 ¥39 / ¥79 / ¥159 每月）
  { id: 'kimi-go', provider: 'kimi', name: 'Go', price: 49, currency: 'CNY', limits: '更多 Agent 积分，文档 / 表格 / PPT、深度研究；年付 ¥39/月', resetKind: 'monthly', fit: '办公文档', source: U.kimi, checked: C },
  { id: 'kimi-plus', provider: 'kimi', name: 'Plus', price: 99, currency: 'CNY', limits: '2 倍 Agent 积分，可用 Kimi Code；年付 ¥79/月', resetKind: 'monthly', coding: true, fit: '写代码 + 办公', source: U.kimi, checked: C },
  { id: 'kimi-pro', provider: 'kimi', name: 'Pro', price: 199, currency: 'CNY', limits: '4 倍 Agent 积分，多任务并行；年付 ¥159/月', resetKind: 'monthly', coding: true, fit: '重度 Agent', source: U.kimi, checked: C },
  // 连续包月原价："Lite ¥118/月 每周 10,000 积分" · "Pro ¥538/月 6倍 Lite 用量额度" · "Max ¥1078/月 14倍 Lite 用量额度"（包季 8 折、包年 7 折）
  { id: 'glm-lite', provider: 'glm', name: 'Coding Lite', price: 118, currency: 'CNY', limits: '每周 10,000 积分，支持 Claude Code 等 20+ 工具；包年 7 折', resetKind: 'weekly', coding: true, codingOnly: true, fit: '日常编程', source: U.glm, checked: C },
  { id: 'glm-pro', provider: 'glm', name: 'Coding Pro', price: 538, currency: 'CNY', limits: 'Lite 的 6 倍用量，生成更快', resetKind: 'weekly', coding: true, codingOnly: true, fit: '高频编程', source: U.glm, checked: C },
  { id: 'glm-max', provider: 'glm', name: 'Coding Max', price: 1078, currency: 'CNY', limits: 'Lite 的 14 倍用量，高峰期资源优先', resetKind: 'weekly', coding: true, codingOnly: true, fit: '深度编程', source: U.glm, checked: C },
  // "Pro 高级套餐 ¥ 200/月 · 每 5 小时6,000 次请求 · 每周45,000 次请求 · 每月90,000 次请求"（Lite 已停售）
  { id: 'qwen-coding-pro', provider: 'qwen', name: 'Coding Plan Pro', price: 200, currency: 'CNY', limits: '每 5 小时 6000 次请求、每周 4.5 万次；可用千问 / GLM / Kimi / MiniMax', resetKind: 'hours', resetHours: 5, coding: true, codingOnly: true, fit: '国内模型编程', source: U.qwen, checked: C },
  // "Coding Plan 个人版 · Lite 套餐 1 个月 40 元/月 · Pro 套餐 1 个月 200 元/月" · 活动页 "Pro Plan 5 倍于 Lite 套餐的用量"
  { id: 'doubao-coding-lite', provider: 'doubao', name: 'Coding Lite', price: 40, currency: 'CNY', limits: '中等强度开发，可用豆包 / DeepSeek / GLM / Kimi，额度按周期恢复', resetKind: 'hours', resetHours: 5, coding: true, codingOnly: true, fit: '入门编程', source: U.doubao, checked: C },
  { id: 'doubao-coding-pro', provider: 'doubao', name: 'Coding Pro', price: 200, currency: 'CNY', limits: 'Lite 的 5 倍用量', resetKind: 'hours', resetHours: 5, coding: true, codingOnly: true, fit: '高强度编程', source: U.doubao, checked: C },
  // "Plus ¥49 /月 · Max ¥119 /月 · Ultra ¥469 /月 · 额度窗口 5 小时固定窗口和周窗口"
  { id: 'minimax-plus', provider: 'minimax', name: 'Token Plus', price: 49, currency: 'CNY', limits: '5 小时窗口 + 周窗口，文本 / 图像 / 语音共享额度', resetKind: 'hours', resetHours: 5, coding: true, codingOnly: true, fit: '轻度编程', source: U.minimax, checked: C },
  { id: 'minimax-max', provider: 'minimax', name: 'Token Max', price: 119, currency: 'CNY', limits: '5 小时窗口 + 周窗口', resetKind: 'hours', resetHours: 5, coding: true, codingOnly: true, fit: '日常编程', source: U.minimax, checked: C },
  { id: 'minimax-ultra', provider: 'minimax', name: 'Token Ultra', price: 469, currency: 'CNY', limits: '5 小时窗口 + 周窗口', resetKind: 'hours', resetHours: 5, coding: true, codingOnly: true, fit: '重度编程', source: U.minimax, checked: C },
]

const A = {
  openai: 'https://developers.openai.com/api/docs/pricing',
  anthropic: 'https://platform.claude.com/docs/en/about-claude/pricing',
  google: 'https://ai.google.dev/gemini-api/docs/pricing',
  deepseek: 'https://api-docs.deepseek.com/zh-cn/quick_start/pricing',
  kimi: 'https://platform.kimi.com/docs/pricing/chat',
  glm: 'https://open.bigmodel.cn/pricing',
  qwen: 'https://help.aliyun.com/zh/model-studio/model-pricing',
  doubao: 'https://www.volcengine.com/docs/82379/1544106',
  minimax: 'https://platform.minimaxi.com/docs/guides/pricing-paygo',
}

/** 每百万 token 的标准价（短上下文 / 最低档），cachedInput 为缓存命中价 */
export const API_MODELS: ApiModel[] = [
  // Standard, short context："gpt-6-astra $10.00 $1.00 … $50.00" · "gpt-6.1-sol $2.00 $0.10 … $10.00" · "gpt-6-luna $0.10 $0.01 … $0.50"
  { id: 'gpt-6-astra', provider: 'chatgpt', name: 'GPT-6 Astra', input: 10, output: 50, cachedInput: 1, currency: 'USD', tier: 'flagship', source: A.openai, checked: C },
  { id: 'gpt-6.1-sol', provider: 'chatgpt', name: 'GPT-6.1 Sol', input: 2, output: 10, cachedInput: 0.1, currency: 'USD', tier: 'balanced', source: A.openai, checked: C },
  { id: 'gpt-6-luna', provider: 'chatgpt', name: 'GPT-6 Luna', input: 0.1, output: 0.5, cachedInput: 0.01, currency: 'USD', tier: 'cheap', source: A.openai, checked: C },
  // "Fable 5.1 $10 / $50 … hits $0.25" · "Opus 5.5 $4 / $20 … $0.20" · "Sonnet 5.5 $2 / $10 … $0.10" · "Haiku 5.5 $0.10 (≤100k) / $0.50 … $0.01"
  { id: 'claude-fable-5.1', provider: 'claude', name: 'Fable 5.1', input: 10, output: 50, cachedInput: 0.25, currency: 'USD', tier: 'flagship', source: A.anthropic, checked: C },
  { id: 'claude-opus-5.5', provider: 'claude', name: 'Opus 5.5', input: 4, output: 20, cachedInput: 0.2, currency: 'USD', tier: 'flagship', source: A.anthropic, checked: C },
  { id: 'claude-sonnet-5.5', provider: 'claude', name: 'Sonnet 5.5', input: 2, output: 10, cachedInput: 0.1, currency: 'USD', tier: 'balanced', source: A.anthropic, checked: C },
  { id: 'claude-haiku-5.5', provider: 'claude', name: 'Haiku 5.5', input: 0.1, output: 0.5, cachedInput: 0.01, currency: 'USD', tier: 'cheap', note: '提示不超过 10 万 token 时', source: A.anthropic, checked: C },
  // "3.1 Pro Preview $2.00, prompts <= 200k … $12.00 … cache $0.20" · "3.8 Flash $0.75 through December 31, 2026 … $3.75 … $0.075" · "3.5 Flash-Lite $0.30 … $2.50 … $0.03"
  { id: 'gemini-3.1-pro', provider: 'gemini', name: '3.1 Pro', input: 2, output: 12, cachedInput: 0.2, currency: 'USD', tier: 'flagship', note: '提示 ≤200k token；预览版', source: A.google, checked: C },
  { id: 'gemini-3.8-flash', provider: 'gemini', name: '3.8 Flash', input: 0.75, output: 3.75, cachedInput: 0.075, currency: 'USD', tier: 'balanced', note: '2026 年底前的优惠价，2027-01-01 起翻倍', source: A.google, checked: C },
  { id: 'gemini-3.5-flash-lite', provider: 'gemini', name: '3.5 Flash-Lite', input: 0.3, output: 2.5, cachedInput: 0.03, currency: 'USD', tier: 'cheap', source: A.google, checked: C },
  // 高峰时段："V4 Pro 缓存命中 0.30元 / 未命中 9.0元 / 输出 27.0元" · "Flash 0.04元 / 2元 / 8元"；"空闲时段价格为高峰时段价格的一半"
  { id: 'deepseek-v4-pro', provider: 'deepseek', name: 'V4 Pro', input: 9, output: 27, cachedInput: 0.3, currency: 'CNY', tier: 'flagship', note: '高峰时段价；工作日 9–12、14–18 点以外半价', source: A.deepseek, checked: C },
  { id: 'deepseek-flash', provider: 'deepseek', name: 'V4.1 Flash', input: 2, output: 8, cachedInput: 0.04, currency: 'CNY', tier: 'cheap', note: '高峰时段价；空闲时段半价', source: A.deepseek, checked: C },
  // "kimi-k3 … ¥2.00 ¥20.00 ¥100.00" · "kimi-k2.6 ¥1.10 ¥6.50 ¥27.00"
  { id: 'kimi-k3', provider: 'kimi', name: 'K3', input: 20, output: 100, cachedInput: 2, currency: 'CNY', tier: 'flagship', source: A.kimi, checked: C },
  { id: 'kimi-k2.6', provider: 'kimi', name: 'K2.6', input: 6.5, output: 27, cachedInput: 1.1, currency: 'CNY', tier: 'balanced', source: A.kimi, checked: C },
  // "GLM-5.3 输入单价 8元 / M 输出单价 28元 / M 缓存命中 2元 / M" · "GLM-5.3-Flash 0.8元 2.8元 0.23元"
  { id: 'glm-5.3', provider: 'glm', name: 'GLM-5.3', input: 8, output: 28, cachedInput: 2, currency: 'CNY', tier: 'flagship', source: A.glm, checked: C },
  { id: 'glm-5.3-flash', provider: 'glm', name: 'GLM-5.3-Flash', input: 0.8, output: 2.8, cachedInput: 0.23, currency: 'CNY', tier: 'cheap', source: A.glm, checked: C },
  // 华北2（北京）："qwen3.8-max 12元 36元" · "qwen3.7-plus 0<Token≤256K 原价2元 / 8元（限时8折）" · "qwen3.8-flash 0.8元 2.7元"；"命中按 10% 计费"
  { id: 'qwen3.8-max', provider: 'qwen', name: 'Qwen3.8-Max', input: 12, output: 36, cachedInput: 1.2, currency: 'CNY', tier: 'flagship', note: '缓存命中按输入价 10% 计', source: A.qwen, checked: C },
  { id: 'qwen3.7-plus', provider: 'qwen', name: 'Qwen3.7-Plus', input: 2, output: 8, cachedInput: 0.2, currency: 'CNY', tier: 'balanced', note: '≤256K 输入；当前限时 8 折，这里按原价算', source: A.qwen, checked: C },
  { id: 'qwen3.8-flash', provider: 'qwen', name: 'Qwen3.8-Flash', input: 0.8, output: 2.7, cachedInput: 0.08, currency: 'CNY', tier: 'cheap', source: A.qwen, checked: C },
  // "doubao-seed-2.1-pro 6.00 … 缓存命中 1.20 … 输出 30.00" · "doubao-seed-2.1-lite 0.80 … 0.16 … 2.70"
  { id: 'doubao-seed-2.1-pro', provider: 'doubao', name: 'Seed 2.1 Pro', input: 6, output: 30, cachedInput: 1.2, currency: 'CNY', tier: 'flagship', source: A.doubao, checked: C },
  { id: 'doubao-seed-2.1-lite', provider: 'doubao', name: 'Seed 2.1 Lite', input: 0.8, output: 2.7, cachedInput: 0.16, currency: 'CNY', tier: 'cheap', source: A.doubao, checked: C },
  // "MiniMax-M3 ≤ 512k 输入 tokens 永久五折 4.20 2.10 | 16.80 8.40 | 0.84 0.42"
  { id: 'minimax-m3', provider: 'minimax', name: 'M3', input: 2.1, output: 8.4, cachedInput: 0.42, currency: 'CNY', tier: 'balanced', note: '≤512k 输入，官方「永久五折」后的价格', source: A.minimax, checked: C },
]

export function providerOf(key: string): Provider {
  return PROVIDERS.find((p) => p.key === key) ?? PROVIDERS[PROVIDERS.length - 1]
}

export const plansOf = (provider: string) => PLANS.filter((p) => p.provider === provider)
export const modelsOf = (provider: string) => API_MODELS.filter((m) => m.provider === provider)

/** 全目录里最晚的核对日期，显示在比价页 */
export function latestCheck() {
  return [...PLANS, ...API_MODELS].map((x) => x.checked).sort().at(-1)
}
