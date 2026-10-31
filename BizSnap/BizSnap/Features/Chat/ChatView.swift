import EventKit
import PhotosUI
import SwiftUI
import UIKit

/// 滚动到底用的恒定锚点：不能挂在流式气泡上（它一收尾就消失，scrollTo 会落空）
private let scrollBottomAnchor = "scroll-bottom-anchor"

struct ChatView: View {
    let thread: ThreadSummary

    /// 打开左侧抽屉
    var onOpenDrawer: () -> Void
    /// 草稿落库后把真实会话 ID 回传给上层
    var onThreadCreated: (String) -> Void
    /// 首轮结束后服务端生成了标题
    var onTitleChanged: (String) -> Void

    @EnvironmentObject private var client: AgentClient

    /// 服务端会话 ID。草稿态为空，发出第一条消息时才创建，避免空会话堆在列表里
    @State private var threadId: String

    @State private var messages: [ChatMessage] = []
    @State private var selected: Set<String> = []
    @State private var text = ""
    @State private var image: UIImage?
    @State private var snapshot: [ContactSnapshot] = []

    @State private var sending = false
    @State private var confirming = false
    /// 流式中的正文与卡片：done 到达后整段换成落库的消息
    @State private var streamingText = ""
    @State private var streamingCards: [ActionCard] = []
    /// 光标只在「正在吐字」时亮：停止吐字 450ms 自动熄，不留一根静止的蓝条
    @State private var caretOn = false
    @State private var caretTask: Task<Void, Never>?
    /// 贴底的延时任务：内容二次变高时要能取消上一轮，避免多次滚动互相打断
    @State private var scrollTask: Task<Void, Never>?
    /// 本轮是否已经收尾：收尾后不再显示等待中的三点，避免卡片出来又闪一下
    @State private var turnDone = true
    @State private var errorText: String?
    @State private var localErrors: [String: CardFailure] = [:]
    /// 真的写进系统的卡片；服务端 confirmed 只是业务库已落库
    @State private var writtenIds: Set<String> = SystemWriteLog.ids

    @State private var title = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var preview: ImagePreviewItem?
    @State private var lastFailed: (text: String, imageBase64: String?)?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showContactsPrimer = false
    @State private var showCalendarPrimer = false

    init(
        thread: ThreadSummary,
        onOpenDrawer: @escaping () -> Void = {},
        onThreadCreated: @escaping (String) -> Void = { _ in },
        onTitleChanged: @escaping (String) -> Void = { _ in }
    ) {
        self.thread = thread
        self.onOpenDrawer = onOpenDrawer
        self.onThreadCreated = onThreadCreated
        self.onTitleChanged = onTitleChanged
        _threadId = State(initialValue: thread.isDraft ? "" : thread.id)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                ScrollViewReader { proxy in
                    ScrollView {
                        // 锚点放在 lazy 栈外面：滚动目标必须始终存在，否则收尾那一刻 scrollTo 会落空
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 12) {
                                if messages.isEmpty && !sending {
                                    emptyHint
                                }

                                ForEach(messages) { message in
                                    messageView(message)
                                        .id(message.id)
                                        // 只用淡入：位移会让已经读到的正文跟着往上跳
                                        .transition(.opacity)
                                }

                                // 等待首字（发消息 / 确认后生成洞察）与正在吐字，都显示这条气泡
                                if !streamingText.isEmpty || ((sending || confirming) && !turnDone) {
                                    streamingBubble
                                }

                                if let errorText {
                                    ErrorBar(text: errorText) {
                                        Task { await retryLast() }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 16)

                            Color.clear.frame(height: 1).id(scrollBottomAnchor)
                        }
                    }
                    // 注意：不要用 .defaultScrollAnchor(.bottom)。它会把「内容不足一屏」的会话整体顶到底部，
                    // 首页出现大片空白、消息看起来挤在下面；内容增长时它还会和手动 scrollTo 抢位置，逐字滚动就会抖。
                    // 打开已有会话靠 messages.count 那一次 pinToBottom 贴底即可。
                    // 拖动立刻收键盘；点空白处也收，但不抢消息里的点击
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
                    // 一轮结束才是卡片真正落位的时候：消息变多、卡片冒出、确认条出现都会让内容变高，
                    // 逐字滚动那一下跟不上，统一交给 pinToBottom 在动画收尾时补位
                    .onChange(of: messages.count) { _, _ in pinToBottom(proxy) }
                    .onChange(of: sending) { _, isSending in
                        guard isSending else { return }
                        pinToBottom(proxy)
                    }
                    // 确认后生成洞察也会先等一会儿：等待气泡出现时要跟到底部
                    .onChange(of: confirming) { _, isConfirming in
                        guard isConfirming else { return }
                        pinToBottom(proxy)
                    }
                    // 卡片随工具返回一张张冒出来：立刻贴底（不带动画），免得和逐字滚动抢同一段动画。
                    // 收尾时的最终位置由 messages.count 那次 pinToBottom 负责
                    .onChange(of: streamingCards.count) { _, _ in
                        proxy.scrollTo(scrollBottomAnchor, anchor: .bottom)
                    }
                    // 确认条出现 / 收起会把气泡区压矮，同样要重新贴底，否则最后一张卡被切一半
                    .onChange(of: pickedCards.count) { _, _ in pinToBottom(proxy) }
                    .onChange(of: errorText) { _, _ in pinToBottom(proxy) }
                    .onChange(of: streamingText) { _, _ in
                        // 逐字跟手，不要动画，否则长回复会一路追着抖
                        proxy.scrollTo(scrollBottomAnchor, anchor: .bottom)
                    }
                }

                if !pickedCards.isEmpty {
                    confirmBar
                }

                Composer(
                    text: $text,
                    image: $image,
                    sending: sending,
                    onSend: { Task { await sendMessage() } },
                    onPickPhoto: { showPhotoPicker = true },
                    onCamera: { showCamera = true }
                )
            }
            // 确认条从底部升起，气泡区同时让位：先贴底再长出按钮，不让它平白压住最后一张卡
            .animation(.easeOut(duration: 0.22), value: pickedCards.count)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    image = picked
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { picked in
                image = picked
            }
        }
        .fullScreenCover(item: $preview) { item in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .onTapGesture { preview = nil }
            }
        }
        .alert("需要通讯录权限", isPresented: $showContactsPrimer) {
            Button("稍后", role: .cancel) {}
            Button("允许") {
                Task {
                    _ = await ContactsService.shared.requestAccess()
                    snapshot = ContactsService.shared.snapshot()
                }
            }
        } message: {
            Text("读取姓名、公司、职位与电话，用来判断这个人是否已经在通讯录里。")
        }
        .alert("需要日历权限", isPresented: $showCalendarPrimer) {
            Button("稍后", role: .cancel) {
                Task { await performConfirm() }
            }
            Button("允许") {
                Task {
                    _ = await CalendarService.shared.requestAccess()
                    await performConfirm()
                }
            }
        } message: {
            Text("确认后的会议会写进系统日历。")
        }
        .alert("重命名会话", isPresented: $showRename) {
            TextField("会话名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                title = name
                Task {
                    guard !threadId.isEmpty else { return }
                    try? await client.renameThread(threadId, title: name)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - 结构

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button {
                hideKeyboard()
                onOpenDrawer()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("对话列表")

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    renameText = title.isEmpty ? thread.displayTitle : title
                    showRename = true
                } label: {
                    Text(title.isEmpty ? thread.displayTitle : title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                HStack(spacing: 5) {
                    Circle()
                        .fill(client.online ? Theme.green : Theme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(client.online ? "服务在线" : "服务未连接")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()

            if confirming {
                ProgressView().tint(Theme.accentSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke.opacity(0.05)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            MessageBubble(message: message) { picked in
                preview = ImagePreviewItem(image: picked)
            }

            if let cards = message.cards {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    CardStrip(
                        card: card,
                        selectable: isSelectable(card),
                        isSelected: selected.contains(card.id),
                        systemWritten: writtenIds.contains(card.id),
                        error: localErrors[card.id],
                        onToggle: { toggle(card) },
                        onRetry: { Task { await retryLocal(card) } },
                        onOpenSettings: { openSettings() }
                    )
                    // 正文先落位，卡片按顺序淡淡浮出，不跟文字一起整体上移
                    .modifier(CardReveal(index: index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    /// 空会话时给一句轻提示，免得整页空得像坏了
    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.accentSoft.opacity(0.85))
            Text("把一段商务对话，\n变成通讯录里的一条记录")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 110)
    }

    /// 等首字：气泡里几根竖条上下起伏，比静态骨架更像「正在想」
    private var skeleton: some View {
        TypingBars()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.stroke.opacity(0.07), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 流式中的临时气泡：先骨架，收到第一个字就换成真实气泡，卡片随工具返回冒出
    @ViewBuilder
    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if streamingText.isEmpty && streamingCards.isEmpty {
                skeleton
            } else {
                if !streamingText.isEmpty {
                    HStack(alignment: .bottom, spacing: 5) {
                        Text(streamingText)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if caretOn {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(Theme.accentSoft)
                                .frame(width: 2, height: 16)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.16), value: caretOn)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.stroke.opacity(0.07), lineWidth: 1)
                    )
                    .frame(maxWidth: 300, alignment: .leading)
                }

                ForEach(streamingCards) { card in
                    CardStrip(
                        card: card,
                        selectable: false,
                        pending: true,
                        isSelected: false,
                        error: nil,
                        onToggle: {},
                        onRetry: {}
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 统一的贴底动作：立刻滚一次，再在卡片浮现动画（0.34s + 序号延迟）收尾时补一次。
    /// 一次滚动只能按当下的内容高度算位置，卡片和确认条往往在那一刻之后才真正占位。
    private func pinToBottom(_ proxy: ScrollViewProxy, delays: [Int] = [0, 200, 620]) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(scrollBottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private var confirmBar: some View {
        Button {
            Task { await confirmSelected() }
        } label: {
            HStack(spacing: 8) {
                if confirming {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("确认选中 \(pickedCards.count) 项")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accentGradient))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .disabled(confirming)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 卡片状态

    /// 每种卡片只认最后一张：补一轮信息后同类卡让位，不同类型互不影响
    /// （同一轮只出会议卡时，上一轮那张联系人卡仍然可勾选）
    private var latestCardIdByKind: [CardKind: String] {
        var result: [CardKind: String] = [:]
        for message in messages where message.hasCards {
            for card in message.cards ?? [] where card.confirmed != true {
                result[card.kind] = card.id
            }
        }
        return result
    }

    private func isSelectable(_ card: ActionCard) -> Bool {
        guard card.confirmed != true, !confirming else { return false }
        return latestCardIdByKind[card.kind] == card.id
    }

    private var selectableCards: [ActionCard] {
        let latest = latestCardIdByKind
        return messages
            .flatMap { $0.cards ?? [] }
            .filter { $0.confirmed != true && latest[$0.kind] == $0.id }
    }

    /// 已勾选且仍有效的卡：被新卡取代的旧卡不计入，也不参与提交
    private var pickedCards: [ActionCard] {
        selectableCards.filter { selected.contains($0.id) }
    }

    private func toggle(_ card: ActionCard) {
        if selected.contains(card.id) {
            selected.remove(card.id)
        } else {
            selected.insert(card.id)
        }
    }

    private func markConfirmed(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for index in messages.indices {
            guard var cards = messages[index].cards else { continue }
            var changed = false
            for cardIndex in cards.indices where ids.contains(cards[cardIndex].id) {
                cards[cardIndex].confirmed = true
                changed = true
            }
            if changed { messages[index].cards = cards }
        }
    }

    // MARK: - 请求

    private func load() async {
        // 顶栏显示会话标题（首轮由服务端生成），没有才退回联系人名
        title = thread.title.isEmpty ? thread.contactName : thread.title
        // 草稿还没有服务端会话，没有历史可拉
        if !threadId.isEmpty {
            do {
                messages = try await client.messages(threadId: threadId)
                if let owner = messages.last(where: { $0.hasCards })?.cards?.first?.contactName, !owner.isEmpty, title.isEmpty {
                    title = owner
                }
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
        await prepareContacts()
        await client.checkHealth()
    }

    /// 草稿在第一条消息时落库，之后一直复用这个 ID
    private func ensureThread() async throws {
        guard threadId.isEmpty else { return }
        threadId = try await client.createThread()
        onThreadCreated(threadId)
    }

    private func prepareContacts() async {
        if ContactsService.shared.status == .notDetermined {
            // 先解释再申请，不直接弹系统弹窗
            showContactsPrimer = true
        }
        snapshot = ContactsService.shared.snapshot()
    }

    /// 收起键盘：输入栏以外的点击、发送之后都要收
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func sendMessage() async {
        hideKeyboard()
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64 = image.flatMap { ImageCompressor.jpegBase64($0) }
        guard !content.isEmpty || base64 != nil else {
            // 选了图却压不出来：不能静默什么都不发生
            if image != nil {
                appendAgentNote(AgentFeedback.imageUnreadable)
            }
            return
        }

        messages.append(.localUser(text: content, imageBase64: base64))
        text = ""
        image = nil
        selected.removeAll()

        await runStream(text: content, imageBase64: base64)
    }

    private func retryLast() async {
        guard let lastFailed else {
            await reloadMessages()
            return
        }
        await runStream(text: lastFailed.text, imageBase64: lastFailed.imageBase64)
    }

    /// 一条流：边收边渲染，`done` 到了才落成正式消息
    private func runStream(text content: String, imageBase64: String?) async {
        sending = true
        streamingText = ""
        streamingCards = []
        errorText = nil
        turnDone = false
        var streamFailed = false

        do {
            try await ensureThread()
            try await client.sendStreaming(
                threadId: threadId,
                text: content,
                imageBase64: imageBase64,
                snapshot: snapshot
            ) { event in
                if case .failed = event { streamFailed = true }
                apply(event, context: .turn)
            }
            lastFailed = streamFailed ? (content, imageBase64) : nil
        } catch {
            turnDone = true
            errorText = error.localizedDescription
            lastFailed = (content, imageBase64)
            settle(fallback: AgentFeedback.disconnected(.turn, reason: error.localizedDescription))
        }

        sending = false
        streamingText = ""
        streamingCards = []
    }

    private func reloadMessages() async {
        guard !threadId.isEmpty else { return }
        do {
            messages = try await client.messages(threadId: threadId)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func confirmSelected() async {
        let cards = pickedCards
        guard !cards.isEmpty else { return }

        let needsCalendar = cards.contains { $0.kind == .createMeeting }
        if needsCalendar && EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            showCalendarPrimer = true
            return
        }
        await performConfirm()
    }

    private func performConfirm() async {
        let cards = pickedCards
        guard !cards.isEmpty else { return }
        confirming = true
        streamingText = ""
        errorText = nil
        turnDone = false

        do {
            try await client.confirmStreaming(threadId: threadId, cards: cards) { event in
                apply(event, context: .confirm)
            }
            selected.removeAll()
        } catch {
            turnDone = true
            errorText = error.localizedDescription
            settle(fallback: AgentFeedback.disconnected(.confirm, reason: error.localizedDescription))
        }

        confirming = false
        streamingText = ""
    }

    // MARK: - 流的统一落点

    /// 一条流的所有事件都在这里变成界面状态；别再在调用处另写一套 switch
    private func apply(_ event: StreamEvent, context: AgentFeedback.Context) {
        switch event {
        case .started:
            break

        case .text(let delta):
            streamingText += delta
            pulseCaret()

        case .card:
            // 卡片不在流式阶段渲染：模型先调工具后写字，卡片必然先到，
            // 放出去就是「按钮先于文字」。等 done 的正式消息一起显示
            break

        case .written(let written, _):
            guard context == .confirm else { return }
            let okIds = Set(written.filter(\.ok).map(\.cardId))
            // 先取要写系统的那批卡，再折叠：折叠会把卡片标成已确认，
            // 之后 pickedCards 就取不到了（会变成「已确认，未写入」还得手点写入）
            let targets = pickedCards.filter { okIds.contains($0.id) }
            // 折叠同样用过阻尼：从整条卡收成一行，不能有回弹
            withAnimation(.interpolatingSpring(stiffness: 1200, damping: 80)) {
                markConfirmed(okIds)
            }
            for item in written where !item.ok {
                localErrors[item.cardId] = CardFailure(
                    message: item.error ?? "写入失败",
                    needsSettings: false
                )
            }
            Task { await writeToSystem(targets) }

        case .done(let message, let insight, _, let newTitle):
            caretTask?.cancel()
            caretOn = false
            turnDone = true
            // 换正式消息：正文原地淡入，卡片在 MessageRow 里逐个浮现
            withAnimation(.easeOut(duration: 0.3)) {
                switch context {
                case .turn:
                    if let message { messages.append(message) }
                    if let newTitle, !newTitle.isEmpty {
                        title = newTitle
                        onTitleChanged(newTitle)
                    }
                case .confirm:
                    let final = (insight?.isEmpty == false ? insight! : streamingText)
                    if !final.isEmpty { appendAgentNote(final) }
                }
                // 同一轮更新里清空，避免正式消息和流式气泡同时出现
                streamingText = ""
                streamingCards = []
            }

        case .title(let value):
            // done 之后补的标题：卡片已经出来了，这里只更新标题栏
            title = value
            onTitleChanged(value)

        case .failed(let message):
            turnDone = true
            errorText = message
            settle(fallback: AgentFeedback.incomplete(context, reason: message))
        }
    }

    /// 每来一个字亮一下；停止吐字 450ms 后自动熄掉，不留一根静止的蓝条在句尾
    private func pulseCaret() {
        caretOn = true
        caretTask?.cancel()
        caretTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            caretOn = false
        }
    }

    /// 收尾：有半截内容就留半截；一句都没有就用给定那句话，绝不留下一条空消息
    private func settle(fallback: String) {
        appendAgentNote(streamingText.isEmpty ? fallback : streamingText)
    }

    /// 任何交互都要落在消息里：只改顶部状态条，用户会以为刚才那一下没生效
    private func appendAgentNote(_ note: String) {
        messages.append(.localAssistant(text: note))
    }

    private func writeToSystem(_ cards: [ActionCard]) async {
        var failures: [(card: ActionCard, message: String)] = []
        for card in cards {
            if let message = await write(card) {
                failures.append((card, message))
            }
        }
        // 系统侧失败也要有话说：卡片只是标红，为什么没成、下一步做什么得讲清
        guard !failures.isEmpty else { return }
        appendAgentNote(
            AgentFeedback.systemWriteFailed(
                failures.map { (label: $0.card.kind.label, who: $0.card.contactName, reason: $0.message) }
            )
        )
    }

    private func retryLocal(_ card: ActionCard) async {
        // 权限还没打开时重试一定失败，直接带去设置页，省一次无效点击
        guard !CardExecutor.needsSettings(for: card) else {
            openSettings()
            return
        }
        if let message = await write(card) {
            appendAgentNote(
                AgentFeedback.retryStillFailed(
                    label: card.kind.label,
                    who: card.contactName,
                    reason: message
                )
            )
        }
    }

    /// 返回失败原因；成功返回 nil
    @discardableResult
    private func write(_ card: ActionCard) async -> String? {
        do {
            _ = try await CardExecutor.execute(card)
            localErrors[card.id] = nil
            writtenIds.insert(card.id)
            return nil
        } catch {
            record(error, for: card.id)
            return error.localizedDescription
        }
    }

    /// 权限类错误单独标出来，界面上换成「去设置」
    private func record(_ error: Error, for cardId: String) {
        localErrors[cardId] = CardFailure(
            message: error.localizedDescription,
            needsSettings: error is SystemAccessError
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 首字到达前的等待：5 根竖条上下起伏，像电平表。
/// 每根按索引错开 0.1s、0.45s 走完一次往返，整体压在 18pt 内，不撑高气泡。
/// 颜色走 Theme.textSecondary（浅色偏深、深色偏亮），两种模式下都不会糊在气泡底上。
private struct TypingBars: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Theme.textSecondary)
                    // 缩放而不是改 frame：只走图形层，不会每一帧触发重排
                    .frame(width: 3, height: 15)
                    .scaleEffect(y: animating ? 0.3 : 1, anchor: .center)
                    .opacity(animating ? 1 : 0.55)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(width: 34, height: 18)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

/// 卡片逐个浮现：正文先落位，按钮再按顺序淡淡出来，不跟文字一起整体上移
private struct CardReveal: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.34).delay(Double(index) * 0.08)) {
                    shown = true
                }
            }
    }
}
