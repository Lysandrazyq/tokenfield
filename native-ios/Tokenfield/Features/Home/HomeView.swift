import SwiftUI
import TokenfieldCore

private enum HomeSheet: Identifiable {
    case account(Account)
    case expiry(Expiry)
    case guide
    var id: String {
        switch self {
        case .account(let value): return "account-\(value.id)"
        case .expiry(let value): return "expiry-\(value.id)"
        case .guide: return "guide"
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: HomeSheet?
    @State private var selectedAccountID: Int?
    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?
    var onShowReport: () -> Void = { }
    var onShowCompare: () -> Void = { }
    var onShowSettings: () -> Void = { }
    var onShowCodex: (() -> Void)? = nil

    private var focus: Account? {
        if let selectedAccountID, let account = store.accounts.first(where: { $0.id == selectedAccountID }) { return account }
        return store.accounts.filter { $0.billing == .subscription }.sorted {
            $0.monthlyCost == $1.monthlyCost ? $0.id < $1.id : $0.monthlyCost > $1.monthlyCost
        }.first ?? store.accounts.first
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ExperiencePage { width in
                VStack(alignment: .leading, spacing: 24) {
                    PageIntro(eyebrow: context.date.formatted(.dateTime.month().day().weekday(.wide)),
                              title: "今天的概览")
                    if let account = focus {
                        overview(compact: width < 720 || typeSize.isAccessibilitySize)
                        AdaptiveColumns(wide: width >= 720 && !typeSize.isAccessibilitySize) {
                            VStack(spacing: 22) {
                                if store.accounts.count > 1 { serviceSwitcher }
                                FocusAccountCard(account: account, now: context.date, edit: { sheet = .account(account) }, onFeedback: showFeedback)
                                otherAccounts
                            }
                        } trailing: {
                            VStack(spacing: 22) {
                                #if os(macOS)
                                if let onShowCodex { CodexStatusCard(onOpen: onShowCodex) }
                                #endif
                                timeline(now: context.date)
                                spendCard
                                if store.usage.isEmpty { gettingStarted }
                                completedExpiries
                            }
                        }
                    } else {
                        AdaptiveColumns(wide: width >= 720 && !typeSize.isAccessibilitySize) {
                            VStack(spacing: 22) {
                                emptyCard
                                #if os(macOS)
                                if let onShowCodex { CodexStatusCard(onOpen: onShowCodex) }
                                #endif
                            }
                        } trailing: {
                            VStack(spacing: 22) {
                                gettingStarted
                                timeline(now: context.date)
                                completedExpiries
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("概览").nativeInlineTitle()
        .toolbar {
            #if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                Button { sheet = .guide } label: { Label("使用指南", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("home.guide")
                Button { sheet = .account(.blank(catalog: store.catalog)) } label: {
                    Label("添加服务", systemImage: "plus")
                }.accessibilityIdentifier("home.add-account")
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .account(.blank(catalog: store.catalog)) } label: {
                    Label("添加服务", systemImage: "plus")
                }.accessibilityIdentifier("home.add-account")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { sheet = .guide } label: { Label("使用指南", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("home.guide")
            }
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            if let feedback {
                UsageFeedback(text: feedback).padding(.horizontal, 16).padding(.bottom, 8)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .account(let account): AccountEditor(account: account)
            case .expiry(let expiry): ExpiryEditor(expiry: expiry)
            case .guide:
                NavigationStack {
                    GettingStartedGuide(onDone: { sheet = nil }).toolbar {
                        #if os(macOS)
                        ToolbarItem(placement: .cancellationAction) { Button("完成") { sheet = nil }.accessibilityIdentifier("guide.done") }
                        #endif
                    }
                }.nativeEditorSize(height: 740)
            }
        }
        .onDisappear { feedbackTask?.cancel(); feedback = nil }
    }

    private func overview(compact: Bool) -> some View {
        let spend = SpendPresentation(backup: store.backup, catalog: store.catalog)
        let today = store.usage.filter { $0.day == DateCodec.day(Date()) }.reduce(0) { partial, item in
            let sum = partial.addingReportingOverflow(item.count)
            return sum.overflow ? Int.max : sum.partialValue
        }
        return NativeCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    overviewAmount(spend)
                    Spacer()
                    Button("查看月报", systemImage: "arrow.up.right", action: onShowReport).buttonStyle(.borderless)
                        .accessibilityIdentifier("home.report")
                }
                VStack(alignment: .leading, spacing: 12) {
                    overviewAmount(spend)
                    Button("查看月报", systemImage: "arrow.up.right", action: onShowReport).buttonStyle(.borderless)
                        .accessibilityIdentifier("home.report")
                }
            }
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label("\(store.accounts.count) 个服务", systemImage: "rectangle.stack")
                        Spacer()
                        Text("今天共记录 \(today) 次").monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(store.accounts.count) 个服务", systemImage: "rectangle.stack")
                        Text("今天共记录 \(today) 次").monospacedDigit()
                    }
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    SummaryMetric(title: "正在管理", value: "\(store.accounts.count) 个服务", symbol: "rectangle.stack")
                    Divider()
                    SummaryMetric(title: "今天记下", value: "\(today) 次", symbol: "checkmark.circle")
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func overviewAmount(_ spend: SpendPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本月支出").font(.subheadline).foregroundStyle(.secondary)
            Text(spend.totalMoney).font(.largeTitle.weight(.semibold))
                .monospacedDigit().modifier(NativeNumericFeedback())
                .fixedSize(horizontal: false, vertical: true)
            Text("按你填写的费用汇总").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var serviceSwitcher: some View {
        HStack {
            Text("记录到哪个服务").font(.headline)
            Spacer()
            Picker("切换服务", selection: Binding(get: { focus?.id ?? 0 }, set: { selectedAccountID = $0 })) {
                ForEach(store.accounts) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44).accessibilityIdentifier("home.service-switcher")
        }.padding(.horizontal, 4)
    }

    private var gettingStarted: some View {
        NativeCard {
            HStack {
                SectionHeading(title: "开始使用", subtitle: "添加、记录，再查看月报")
                Button { sheet = .guide } label: { Image(systemName: "arrow.up.right") }
                    .frame(minWidth: 44, minHeight: 44).accessibilityLabel("查看使用指南")
            }
            NumberedGuideRow(number: 1, title: "添加服务", detail: "选择你在用的 AI，核对实际费用。", complete: !store.accounts.isEmpty)
            NumberedGuideRow(number: 2, title: "记一次用量", detail: "用完点一下用途，记错可以撤销。", complete: !store.usage.isEmpty)
            NumberedGuideRow(number: 3, title: "看看本月花费", detail: "月报会自动汇总，月底可以保存。", complete: !store.statements.isEmpty)
        }
    }

    private func showFeedback(_ text: String) {
        feedbackTask?.cancel()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { feedback = text }
        feedbackTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { feedback = nil }
        }
    }

    private var emptyCard: some View {
        NativeCard {
            Image(systemName: "rectangle.stack.badge.plus").font(.largeTitle).foregroundStyle(.secondary).padding(.bottom, 4)
            Text("添加你正在用的 AI").font(.title2.weight(.semibold))
            Text("记下订阅费用或余额。之后可以一键记录用量，查看重置时间与本月花费。")
                .font(.subheadline).foregroundStyle(.secondary)
            NativeControlGroup {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { emptyActions }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { emptyActions }
                        VStack(alignment: .leading, spacing: 12) { emptyActions }
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyActions: some View {
        Button("添加服务", systemImage: "plus") { sheet = .account(.blank(catalog: store.catalog)) }
            .modifier(PrimaryActionStyle()).fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .accessibilityIdentifier("home.empty-add-account")
        Button("费用对比", action: onShowCompare).modifier(SecondaryActionStyle())
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        Button("导入已有备份", action: onShowSettings).buttonStyle(.borderless).font(.subheadline).frame(minHeight: 44)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }

    @ViewBuilder private var otherAccounts: some View {
        let others = store.accounts.filter { $0.id != focus?.id }
        if !others.isEmpty {
            NativeCard {
                NativeSectionTitle(title: "其他 AI")
                ForEach(others) { account in
                    Button { sheet = .account(account) } label: {
                        HStack(spacing: 12) {
                            ProviderBadge(provider: store.catalog.provider(account.provider))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name).font(.headline)
                                Text(account.billing.label).font(.caption).foregroundStyle(.secondary)
                                if account.billing == .balance, let balance = account.balance {
                                    Text("余额 \(NativeFormat.money(balance, currency: account.currency))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(NativeFormat.money(account.monthlyCost, currency: account.currency)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("home.account.\(account.id)")
                    if account.id != others.last?.id { Divider() }
                }
            }
        }
    }

    private var spendCard: some View {
        let spend = SpendPresentation(backup: store.backup, catalog: store.catalog)
        let slices = spend.slices
        return Button(action: onShowReport) {
            NativeCard {
                HStack {
                    Text("支出构成").font(.headline)
                    Spacer()
                    Label("月报", systemImage: "chevron.right").font(.subheadline).foregroundStyle(.tint)
                }
                Text("每个服务的花费占比").font(.caption).foregroundStyle(.secondary)
                if spend.hasSpend {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(slices) { slice in
                                NativeFormat.color(slice.color).frame(width: max(0, geometry.size.width * spend.fraction(for: slice)))
                            }
                        }.clipShape(Capsule())
                    }.frame(height: 8).accessibilityHidden(true)
                }
                ForEach(slices) { slice in
                    HStack {
                        Circle().fill(NativeFormat.color(slice.color)).frame(width: 8, height: 8)
                        Text(slice.account.name)
                        Spacer(minLength: 8)
                        Text("\(spend.percentage(for: slice))% · \(spend.money(for: slice))").monospacedDigit()
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("home.spend-breakdown")
    }

    @ViewBuilder private func timeline(now: Date) -> some View {
        let events = Schedule.timeline(accounts: store.accounts, expiries: store.expiries, now: now)
        let overdue = events.filter { $0.kind == .expiry && $0.date <= now }
        let upcoming = events.filter { $0.date > now }
        if !overdue.isEmpty {
            NativeCard {
                NativeSectionTitle(title: "已过期")
                ForEach(overdue) { event in eventRow(event, now: now) }
            }
        }
        NativeCard {
            HStack {
                NativeSectionTitle(title: "接下来")
                Button("添加到期项", action: addExpiry).font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("home.add-expiry")
            }
            if upcoming.isEmpty {
                Text("暂时没有即将到来的事项。可以添加重置券、免费试用或赠送额度。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(upcoming.prefix(8)) { event in eventRow(event, now: now) }
            }
        }
    }

    private func eventRow(_ event: TimelineEvent, now: Date) -> some View {
        Button { open(event) } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: event.kind == .renew ? "creditcard" : event.kind == .reset ? "arrow.clockwise" : "clock")
                    .foregroundStyle(event.date <= now ? Color.red : Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.subheadline.weight(.medium))
                    Text("\(event.kind.label) · \(event.date.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(Schedule.countdown(event.date, now: now)).font(.caption).monospacedDigit()
                    .foregroundStyle(event.kind != .reset && event.date.timeIntervalSince(now) < store.settings.remindHours * 3600 ? Color.orange : Color.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()).padding(.vertical, 4)
        }.buttonStyle(.plain).accessibilityIdentifier("home.event.\(event.id)")
    }

    @ViewBuilder private var completedExpiries: some View {
        let completed = store.expiries.filter(\.done)
        if !completed.isEmpty {
            NativeCard {
                DisclosureGroup("已完成到期项（\(completed.count)）") {
                    ForEach(completed) { expiry in
                        Button { sheet = .expiry(expiry) } label: {
                            Label(expiry.title, systemImage: "checkmark.circle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 8)
                        }.buttonStyle(.plain)
                    }
                }.font(.subheadline)
            }
        }
    }

    private func addExpiry() {
        let week = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let date = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: week) ?? week
        sheet = .expiry(Expiry(title: "完全重置券", expiresAt: DateCodec.iso(date)))
    }

    private func open(_ event: TimelineEvent) {
        if let id = event.expiryID, let expiry = store.expiries.first(where: { $0.id == id }) { sheet = .expiry(expiry) }
        else if let id = event.accountID, let account = store.accounts.first(where: { $0.id == id }) { sheet = .account(account) }
    }
}

private struct FocusAccountCard: View {
    @Environment(AppStore.self) private var store
    let account: Account
    let now: Date
    let edit: () -> Void
    let onFeedback: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var report: ValueReport {
        Finance.valueReport(account: account, usage: store.usage, settings: store.settings,
                            model: store.catalog.models.first { $0.id == account.modelId }, now: now)
    }
    private var todayCount: Int {
        store.usage.filter { $0.accountId == account.id && $0.day == DateCodec.day(now) }.reduce(0) {
            let (sum, overflow) = $0.addingReportingOverflow($1.count)
            return overflow ? Int.max : sum
        }
    }

    var body: some View {
        NativeCard {
            Button(action: edit) {
                HStack(spacing: 12) {
                    ProviderBadge(provider: store.catalog.provider(account.provider), size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name).font(.title3.weight(.semibold))
                        Text(store.catalog.plans.first { $0.id == account.planId }?.name ?? account.billing.label)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("home.account.\(account.id)")
            if let reset = Schedule.nextReset(account, now: now) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise").font(.title2).frame(width: 38, height: 38)
                        .background(Color.primary.opacity(0.055), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Schedule.countdown(reset, now: now)).font(.title3.weight(.semibold)).monospacedDigit()
                        Text("重置于 \(reset.formatted(.dateTime.month().day().hour().minute()))").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            }
            SectionHeading(title: "记录一次用量", subtitle: "手动记次数，不代表官方剩余额度。")
            NativeControlGroup {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Intensity.allCases, id: \.self) { intensity in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                if store.logUsage(accountID: account.id, intensity: intensity) {
                                    onFeedback("已记录 1 次 · \(intensity.usageTitle)")
                                }
                            }
                        } label: {
                            Label(intensity.usageTitle, systemImage: usageSymbol(intensity.rawValue))
                                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 34)
                        }.modifier(SecondaryActionStyle())
                            .accessibilityHint("为 \(account.name) 记录一次\(intensity.usageTitle)，可撤销")
                            .accessibilityIdentifier("home.log.\(intensity.rawValue)")
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { usageCount; Spacer(minLength: 8); undoAction }
                VStack(alignment: .leading, spacing: 4) { usageCount; undoAction }
            }
            Divider()
            DisclosureGroup("看看这个周期用得值不值") { valueSection.padding(.top, 12) }
                .font(.subheadline).accessibilityIdentifier("home.value-details")
        }
        #if os(iOS)
        .sensoryFeedback(.success, trigger: todayCount)
        #endif
    }

    private var usageCount: some View {
        Text("今天 \(todayCount) 次").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .modifier(NativeNumericFeedback())
    }

    @ViewBuilder private var undoAction: some View {
        if let entry = store.undoableUsage(accountID: account.id) {
            Button("撤销上次\(entry.intensity.usageTitle)") {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    if store.undoLastUsage(accountID: account.id) { onFeedback("已撤销上次记录") }
                }
            }
            .font(.caption).frame(minHeight: 44)
            .accessibilityHint("撤销本机在 \(entry.day) 记下的一次用量")
            .accessibilityIdentifier("home.undo-usage")
        }
    }

    @ViewBuilder private var valueSection: some View {
        HStack {
            Text("这个周期用得值不值").font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Text("已过 \(Int((report.elapsed * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
        }
        if report.verdict == .unknown {
            Text(account.modelId == nil ? "编辑账号选择一个对照的 API 模型，就能估算同样用量按量付费要多少钱。" : "每次用完点一下下面的按钮，用几天就能估算会员值不值。")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            Text(NativeFormat.money(report.apiEquivalent)).font(.title.bold()).monospacedDigit()
            Text("预计按量付费等价 · 会员 \(NativeFormat.money(report.fee))").font(.caption).foregroundStyle(.secondary)
            if let progress = NativeFormat.progressValue(numerator: report.apiEquivalent, denominator: report.fee) {
                ProgressView(value: progress).tint(report.verdict == .great ? .green : .accentColor)
            }
            Text(verdictText).font(.subheadline).foregroundStyle(.secondary)
            if report.limitDays > 0 {
                Text("这周期有 \(report.limitDays) 天碰到了上限。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var verdictText: String {
        switch report.verdict {
        case .great: return "按目前用量，会员比按量付费划算。"
        case .ok: return "用到月费的一半以上了，再多用点就回本。"
        case .low: return "按目前用量，换成按量付费会更省。"
        case .unknown: return ""
        }
    }
}
