import EventKit
import PhotosUI
import SwiftUI

struct ChatView: View {
    let thread: ThreadSummary

    @EnvironmentObject private var client: AgentClient
    @Environment(\.dismiss) private var dismiss

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
    @State private var localErrors: [String: String] = [:]

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

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                messageView(message)
                                    .id(message.id)
                            }

                            if sending {
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
                    .scrollDismissesKeyboard(.interactively)
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

                if !selected.isEmpty {
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
        .navigationBarBackButtonHidden(true)
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
                Task { try? await client.renameThread(thread.id, title: name) }
            }
        }
        .task { await load() }
    }

    // MARK: - 结构

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.elevated.opacity(0.8)))
            }
            .accessibilityLabel("返回")

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
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
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
                        selectable: isSelectable(card, in: message),
                        isSelected: selected.contains(card.id),
                        error: localErrors[card.id],
                        onToggle: { toggle(card) },
                        onRetry: { Task { await retryLocal(card) } }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
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
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
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
                    Text("确认选中 \(selected.count) 项")
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

    private var latestCardMessageId: String? {
        messages.last(where: \.hasCards)?.id
    }

    private func isSelectable(_ card: ActionCard, in message: ChatMessage) -> Bool {
        guard card.confirmed != true else { return false }
        return message.id == latestCardMessageId && !confirming
    }

    private var selectableCards: [ActionCard] {
        guard let id = latestCardMessageId,
              let message = messages.first(where: { $0.id == id }) else { return [] }
        return (message.cards ?? []).filter { $0.confirmed != true }
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
        title = thread.contactName.isEmpty ? thread.title : thread.contactName
        do {
            messages = try await client.messages(threadId: thread.id)
            if let owner = messages.last(where: { $0.hasCards })?.cards?.first?.contactName, !owner.isEmpty, title.isEmpty {
                title = owner
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        await prepareContacts()
        await client.checkHealth()
    }

    private func prepareContacts() async {
        if ContactsService.shared.status == .notDetermined {
            // 先解释再申请，不直接弹系统弹窗
            showContactsPrimer = true
        }
        snapshot = ContactsService.shared.snapshot()
    }

    private func sendMessage() async {
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

        do {
            try await client.sendStreaming(
                threadId: thread.id,
                text: content,
                imageBase64: imageBase64,
                snapshot: snapshot
            ) { event in
                switch event {
                case .text(let delta):
                    streamingText += delta
                case .card(let card):
                    streamingCards.append(card)
                case .done(let message, _, _):
                    if let message { messages.append(message) }
                case .failed(let message):
                    errorText = message
                default:
                    break
                }
            }
            lastFailed = nil
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
        do {
            messages = try await client.messages(threadId: thread.id)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func confirmSelected() async {
        let cards = selectableCards.filter { selected.contains($0.id) }
        guard !cards.isEmpty else { return }

        let needsCalendar = cards.contains { $0.kind == .createMeeting }
        if needsCalendar && EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            showCalendarPrimer = true
            return
        }
        await performConfirm()
    }

    private func performConfirm() async {
        let cards = selectableCards.filter { selected.contains($0.id) }
        guard !cards.isEmpty else { return }
        confirming = true
        streamingText = ""
        errorText = nil

        do {
            try await client.confirmStreaming(threadId: thread.id, cards: cards) { event in
                switch event {
                case .written(let written, let contactName):
                    // 事务已提交：先把卡片折叠掉，再去写系统通讯录 / 日历
                    let okIds = Set(written.filter(\.ok).map(\.cardId))
                    markConfirmed(okIds)
                    for item in written where !item.ok {
                        localErrors[item.cardId] = item.error ?? "写入失败"
                    }
                    if !contactName.isEmpty { title = contactName }
                    let targets = cards.filter { okIds.contains($0.id) }
                    Task { await writeToSystem(targets) }

                case .text(let delta):
                    streamingText += delta

                case .done(_, let insight, let contactName):
                    let final = (insight?.isEmpty == false ? insight! : streamingText)
                    if !final.isEmpty {
                        messages.append(.localAssistant(text: final))
                    }
                    if !contactName.isEmpty { title = contactName }

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
            do {
                _ = try await CardExecutor.execute(card)
                localErrors[card.id] = nil
            } catch {
                localErrors[card.id] = error.localizedDescription
            }
        }
    }

    private func retryLocal(_ card: ActionCard) async {
        do {
            _ = try await CardExecutor.execute(card)
            localErrors[card.id] = nil
        } catch {
            localErrors[card.id] = error.localizedDescription
        }
    }
}

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}
