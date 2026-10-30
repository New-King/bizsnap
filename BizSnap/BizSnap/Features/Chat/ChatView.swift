import EventKit
import PhotosUI
import SwiftUI
import UIKit

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
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty && !sending {
                                emptyHint
                            }

                            ForEach(messages) { message in
                                messageView(message)
                                    .id(message.id)
                            }

                            if sending || !streamingText.isEmpty {
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
                    }
                    // 拖动立刻收键盘；点空白处也收，但不抢消息里的点击
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: sending) { _, isSending in
                        guard isSending else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("stream-end", anchor: .bottom)
                        }
                    }
                    .onChange(of: streamingText) { _, _ in
                        proxy.scrollTo("stream-end", anchor: .bottom)
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
                ForEach(cards) { card in
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

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 220, height: 14)
                .shimmering()
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 150, height: 14)
                .shimmering()
        }
        .padding(14)
        .frame(maxWidth: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.5)))
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
                        Rectangle()
                            .fill(Theme.accentSoft)
                            .frame(width: 2, height: 15)
                    }
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
        .id("stream-end")
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
        guard !content.isEmpty || base64 != nil else { return }

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
        var streamFailed = false

        do {
            try await ensureThread()
            try await client.sendStreaming(
                threadId: threadId,
                text: content,
                imageBase64: imageBase64,
                snapshot: snapshot
            ) { event in
                switch event {
                case .text(let delta):
                    streamingText += delta
                case .card(let card):
                    streamingCards.append(card)
                case .done(let message, _, _, let newTitle):
                    if let message { messages.append(message) }
                    if let newTitle, !newTitle.isEmpty {
                        title = newTitle
                        onTitleChanged(newTitle)
                    }
                    // 同一轮更新里清空，避免正式消息和流式气泡同时出现
                    streamingText = ""
                    streamingCards = []
                case .failed(let message):
                    errorText = message
                    streamFailed = true
                default:
                    break
                }
            }
            lastFailed = streamFailed ? (content, imageBase64) : nil
            if streamFailed, !streamingText.isEmpty {
                messages.append(.localAssistant(text: streamingText))
            }
        } catch {
            errorText = error.localizedDescription
            lastFailed = (content, imageBase64)
            // 已经吐出来的片段留着，标成未完成，别让用户白等一场
            if !streamingText.isEmpty {
                messages.append(.localAssistant(text: streamingText))
            }
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

        do {
            try await client.confirmStreaming(threadId: threadId, cards: cards) { event in
                switch event {
                case .written(let written, _):
                    // 事务已提交：先把卡片折叠掉，再去写系统通讯录 / 日历
                    let okIds = Set(written.filter(\.ok).map(\.cardId))
                    markConfirmed(okIds)
                    for item in written where !item.ok {
                        localErrors[item.cardId] = CardFailure(
                            message: item.error ?? "写入失败",
                            needsSettings: false
                        )
                    }
                    let targets = cards.filter { okIds.contains($0.id) }
                    Task { await writeToSystem(targets) }

                case .text(let delta):
                    streamingText += delta

                case .done(_, let insight, _, _):
                    let final = (insight?.isEmpty == false ? insight! : streamingText)
                    if !final.isEmpty {
                        messages.append(.localAssistant(text: final))
                    }
                    streamingText = ""

                case .failed(let message):
                    errorText = message

                default:
                    break
                }
            }
            selected.removeAll()
        } catch {
            errorText = error.localizedDescription
        }

        confirming = false
        streamingText = ""
    }

    private func writeToSystem(_ cards: [ActionCard]) async {
        for card in cards {
            await write(card)
        }
    }

    private func retryLocal(_ card: ActionCard) async {
        // 权限还没打开时重试一定失败，直接带去设置页，省一次无效点击
        guard !CardExecutor.needsSettings(for: card) else {
            openSettings()
            return
        }
        await write(card)
    }

    private func write(_ card: ActionCard) async {
        do {
            _ = try await CardExecutor.execute(card)
            localErrors[card.id] = nil
            writtenIds.insert(card.id)
        } catch {
            record(error, for: card.id)
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
