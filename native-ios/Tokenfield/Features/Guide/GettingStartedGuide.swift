import SwiftUI

struct WelcomeView: View {
    let onAddAccount: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    private let steps = [
        ("把常用 AI 放在一起", "会员订阅、按量付费和余额，都有一个清楚的位置。", "rectangle.stack", "添加服务"),
        ("用完，轻轻记一下", "选择问答、写作、代码或长任务。记错了，也能立即撤销。", "hand.tap", "记录用量"),
        ("每月，看清钱花在哪", "费用自动汇总成月报，保存或分享，一张就够。", "chart.pie", "查看月报")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text("Tokenfield").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(page + 1) / 3").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    WelcomeIllustration(page: page)
                        .frame(height: 210).frame(maxWidth: .infinity)
                        .id(page).transition(reduceMotion ? .identity : .opacity)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(steps[page].0).font(.title.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(steps[page].1).font(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index == page ? Color.primary : Color.primary.opacity(0.12))
                                .frame(width: index == page ? 26 : 7, height: 5)
                        }
                    }.accessibilityLabel("第 \(page + 1) 步，共 3 步")
                    Text("手动记录，不读取聊天内容，也不需要 API Key。费用与使用价值属于估算，以实际账单为准。")
                        .font(.caption).foregroundStyle(.secondary)
                    NativeControlGroup {
                        VStack(spacing: 12) {
                            Button {
                                if page == 2 { onAddAccount() }
                                else { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { page += 1 } }
                            } label: {
                                HStack {
                                    Text(page == 2 ? "添加第一个服务" : "下一步")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }.frame(minHeight: 28)
                            }
                            .modifier(PrimaryActionStyle())
                            .accessibilityIdentifier(page == 2 ? "welcome.add-account" : "welcome.next")
                            if page > 0 {
                                Button("上一步") { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { page -= 1 } }
                                    .frame(minHeight: 44).accessibilityIdentifier("welcome.back")
                            }
                        }
                    }
                }
                .frame(maxWidth: 470, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
            .background { AppBackdrop() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后再说", action: onDismiss).accessibilityIdentifier("welcome.skip")
                }
            }
        }
        .nativeEditorSize(height: 750)
    }
}

private struct WelcomeIllustration: View {
    let page: Int
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.primary.opacity(0.025))
                .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(Color.primary.opacity(0.04), lineWidth: 1) }
            if page == 0 {
                HStack(spacing: -16) {
                    sampleCard("sparkles", "Claude", rotation: -9)
                    sampleCard("bubble.left.and.bubble.right", "ChatGPT", rotation: 7)
                }
            } else if page == 1 {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48, weight: .light))
                    Text("今天 1 次").font(.title2.weight(.semibold)).monospacedDigit()
                    HStack(spacing: 8) {
                        ForEach(["问答", "写作", "代码"], id: \.self) { text in
                            Text(text).font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.nativePageBackground, in: Capsule())
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("本月支出"); Spacer(); Image(systemName: "chart.pie") }
                        .font(.caption).foregroundStyle(.secondary)
                    Text("¥ 208.00").font(.largeTitle.weight(.semibold))
                    HStack(spacing: 4) {
                        Capsule().fill(Color.primary).frame(width: 85)
                        Capsule().fill(Color.primary.opacity(0.35)).frame(width: 54)
                        Capsule().fill(Color.primary.opacity(0.13))
                    }.frame(height: 6)
                    Text("示意数据").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(22).frame(width: 240)
                .background(Color.nativePageBackground, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }
    private func sampleCard(_ symbol: String, _ title: String, rotation: Double) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.headline)
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.15)).frame(width: 64, height: 4)
        }
        .padding(22).frame(width: 146, height: 150, alignment: .leading)
        .background(Color.nativePageBackground, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
        .shadow(color: .black.opacity(0.07), radius: 15, y: 9)
        .rotationEffect(.degrees(rotation))
    }
}

struct GettingStartedGuide: View {
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)? = nil
    var body: some View {
        ExperiencePage(maximumWidth: 820) { width in
            VStack(alignment: .leading, spacing: 24) {
                PageIntro(eyebrow: "使用指南", title: "添加、记录、查看", detail: "从一个常用服务开始，其他设置可以以后再补。")
                    .accessibilityIdentifier("guide.title")
                NativeCard {
                    NumberedGuideRow(number: 1, title: "添加你正在用的服务", detail: "在「概览」点「添加服务」，选择服务和套餐，再核对实际费用。参考价可修改，自定义服务也能记录。")
                    Divider()
                    NumberedGuideRow(number: 2, title: "每次用完，记一下", detail: "这是手动记录：选择主要用途，就记下一次用量。点「撤销上次」可以改正，不会读取你的聊天内容。")
                    Divider()
                    NumberedGuideRow(number: 3, title: "月底查看与保存月报", detail: "「月报」会汇总费用。保存本月会留下当时的账本，之后修改服务，也不影响已保存的月份。")
                }
                NativeCard {
                    SectionHeading(title: "什么时候重置，怎么提醒？")
                    Text("在服务的「额度与提醒」里填写重置方式和时间；重置券、试用和赠送额度可在概览里「添加到期项」。通知需要你主动开启权限。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                NativeCard {
                    SectionHeading(title: "这几个数字，分别代表什么")
                    LabeledContent("本月支出", value: "你填写的月费或预计花费")
                    LabeledContent("使用次数", value: "你手动记下的记录")
                    Text("按量等价费用是根据使用类型与假设 token 数估算的参考值，不是实际账单，也不代表服务商的剩余额度。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NativeCard {
                    SectionHeading(title: "备份与双端使用")
                    Text("在「设置 → 导出备份」保存 JSON；换设备后可导入。导入会替换现有数据，操作前会确认。iPhone / Mac 使用相同的记录格式；自动同步是否可用，以设置中的 iCloud 状态为准。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .nativeEditingBar(isEditing: true) {
            HStack {
                Spacer()
                Button("完成") {
                    if let onDone { onDone() } else { dismiss() }
                }
                .modifier(PrimaryActionStyle())
                .accessibilityIdentifier("guide.done")
            }
        }
        .navigationTitle("使用指南").nativeInlineTitle()
    }
}
