import dayjs from 'dayjs'
import type { Account, Intensity, Settings, Usage } from '../db'
import { toCNY } from '../db'
import type { ApiModel } from '../data/pricing'

/**
 * 「会员值不值」的估算模型。
 *
 * 每种使用强度对应一次使用大约消耗多少 token（输入含上下文 / 输出）。
 * 这些是估算值，来源和推导写在 PROFILES 的 basis 里，界面上会原样展示，让用户知道是怎么算的。
 */

export interface UsageProfile {
  key: Intensity
  label: string
  /** 按钮上用的短名 */
  short: string
  /** 一次使用的输入 token（含历史上下文、附件） */
  input: number
  /** 一次使用的输出 token */
  output: number
  /** 输入里能命中缓存的比例（多轮对话、Agent 反复读同一批文件时很高） */
  cacheRatio: number
  example: string
  basis: string
}

export const PROFILES: UsageProfile[] = [
  {
    key: 'chat',
    short: '问答',
    label: '日常问答',
    input: 1_500,
    output: 500,
    cacheRatio: 0.3,
    example: '查资料、问问题、翻译一段话',
    basis: '回答约 800 字、带几轮历史；官方换算 1 token ≈ 1.5–2 个汉字',
  },
  {
    key: 'write',
    short: '写作',
    label: '写作 / 读文档',
    input: 8_000,
    output: 1_500,
    cacheRatio: 0.4,
    example: '改一篇稿子、总结一份 PDF、写邮件',
    basis: '贴进去约 1 万字的材料，输出两千来字',
  },
  {
    key: 'code',
    short: '写代码',
    label: '写代码（对话式）',
    input: 20_000,
    output: 2_500,
    cacheRatio: 0.6,
    example: '在网页里贴代码、让它改 bug、解释报错',
    basis: '每次带上几个文件和报错，输出一段代码',
  },
  {
    key: 'agent',
    short: 'Agent',
    label: '编程 Agent',
    input: 2_000_000,
    output: 20_000,
    cacheRatio: 0.92,
    example: 'Claude Code / Codex / Cursor 自动改一整个功能',
    basis: '一个任务要反复读文件、跑命令几十轮，九成以上输入命中缓存。按 Anthropic 官方数据校准：Claude Code 平均每人每个工作日约 $13、每月 $150–250',
  },
]

export const profileOf = (k: Intensity) => PROFILES.find((p) => p.key === k) ?? PROFILES[0]

/** 一次使用按 API 计价要多少钱（模型币种） */
export function costPerUse(profile: UsageProfile, m: ApiModel) {
  const cached = m.cachedInput ?? m.input
  const inCost = (profile.input * (1 - profile.cacheRatio) * m.input + profile.input * profile.cacheRatio * cached) / 1e6
  return inCost + (profile.output * m.output) / 1e6
}

/** 每月用多少次，按量付费才和会员一样贵（回本点） */
export function breakEvenUses(monthlyFeeCNY: number, profile: UsageProfile, m: ApiModel, usdRate: number) {
  const per = toCNY(costPerUse(profile, m), m.currency, usdRate)
  return per > 0 ? monthlyFeeCNY / per : Infinity
}

export interface ValueReport {
  /** 本周期已过去的比例 */
  elapsed: number
  /** 本周期至今使用次数 */
  uses: number
  /** 按目前节奏，整个周期预计次数 */
  projected: number
  /** 同样的用量换成 API 大约多少钱（CNY） */
  apiEquivalent: number
  /** 会员月费（CNY） */
  fee: number
  /** 平均每次花多少（CNY） */
  perUse: number
  /** 这周期碰到上限的天数 */
  limitDays: number
  verdict: 'great' | 'ok' | 'low' | 'unknown'
}

/** 当前计费周期：有续费日就按续费日切，没有就按自然月 */
export function cycleOf(a: Account, now = dayjs()) {
  if (a.renewAt) {
    let end = dayjs(a.renewAt)
    while (end.isBefore(now)) end = end.add(1, 'month')
    return { start: end.subtract(1, 'month'), end }
  }
  return { start: now.startOf('month'), end: now.endOf('month') }
}

export function valueReport(a: Account, usage: Usage[], settings: Settings, model?: ApiModel, now = dayjs()): ValueReport {
  const { start, end } = cycleOf(a, now)
  const inCycle = usage.filter((u) => u.accountId === a.id && !dayjs(u.day).isBefore(start, 'day') && !dayjs(u.day).isAfter(end, 'day'))
  const uses = inCycle.reduce((s, u) => s + u.count, 0)
  const elapsed = Math.min(1, Math.max(0.03, now.diff(start) / end.diff(start)))
  const projected = uses / elapsed
  const fee = toCNY(a.monthlyCost || 0, a.currency, settings.usdRate)
  let api = 0
  if (model) for (const u of inCycle) api += toCNY(costPerUse(profileOf(u.intensity), model), model.currency, settings.usdRate) * u.count
  const apiEquivalent = api / elapsed
  const verdict: ValueReport['verdict'] = !model || uses === 0 ? 'unknown' : apiEquivalent >= fee ? 'great' : apiEquivalent >= fee * 0.5 ? 'ok' : 'low'
  return {
    elapsed,
    uses,
    projected,
    apiEquivalent,
    fee,
    perUse: projected > 0 ? fee / projected : 0,
    limitDays: inCycle.filter((u) => u.hitLimit).length,
    verdict,
  }
}
