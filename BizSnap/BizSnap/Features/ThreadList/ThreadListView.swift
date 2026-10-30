import SwiftUI

struct ThreadListView: View {
    @EnvironmentObject private var client: AgentClient

    @State private var threads: [ThreadSummary] = []
    @State private var path: [ThreadSummary] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var showSettings = false
    @State private var creating = false
    @State private var renaming: ThreadSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    // 错误条放在所有状态之上：空列表时点新建失败也能立刻看到原因
                    if let errorText {
                        ErrorBar(text: errorText) {
                            Task { await reload() }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    if loading {
                        loadingRows
                    } else if threads.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                    Spacer(minLength: 0)
                }

                newThreadButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 28)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ThreadSummary.self) { thread in
                ChatView(thread: thread)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.surface)
            }
            .alert("重命名会话", isPresented: renameBinding) {
                TextField("会话名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") { Task { await applyRename() } }
            }
            .task(id: path.count) { await reload() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("会话")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.elevated.opacity(0.8)))
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.gap) {
                ForEach(threads) { thread in
                    Button {
                        path.append(thread)
                    } label: {
                        ThreadRow(thread: thread)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameText = thread.displayTitle
                            renaming = thread
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await delete(thread) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .refreshable { await reload() }
    }

    private var loadingRows: some View {
        VStack(spacing: Theme.gap) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.7))
                    .frame(height: 64)
                    .shimmering()
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accentSoft)
                Text("把一段商务对话，\n变成通讯录里的一条记录")
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                Text("贴一张聊天截图，或直接打一句话")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .foregroundStyle(Theme.stroke.opacity(0.16))
            )
            .padding(.horizontal, 24)

            Button {
                Task { await startThread() }
            } label: {
                Text("开始第一段对话")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accentGradient))
            }
            .padding(.horizontal, 24)
            .disabled(creating)

            Spacer()
        }
    }

    private var newThreadButton: some View {
        Button {
            Task { await startThread() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.accentGradient))
                .shadow(color: Theme.accent.opacity(0.45), radius: 16, y: 8)
        }
        .disabled(creating)
        .accessibilityLabel("新建会话")
    }

    // MARK: - 动作

    private func reload() async {
        loading = threads.isEmpty
        do {
            threads = try await client.listThreads()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func startThread() async {
        creating = true
        defer { creating = false }
        do {
            let id = try await client.createThread()
            let thread = ThreadSummary(id: id, title: "", contactName: "", lastMessage: "", updatedAt: "")
            threads.insert(thread, at: 0)
            path.append(thread)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    private func applyRename() async {
        guard let thread = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        do {
            try await client.renameThread(thread.id, title: name)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ thread: ThreadSummary) async {
        do {
            try await client.deleteThread(thread.id)
            threads.removeAll { $0.id == thread.id }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                Text(thread.avatarText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentSoft)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(thread.lastMessage.isEmpty ? "还没有消息" : thread.lastMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(thread.updatedAt.shortTime)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .glassCard(padding: 12)
        .contentShape(Rectangle())
    }
}

struct ErrorBar: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.red)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("重试", action: onRetry)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.red.opacity(0.12))
        )
    }
}

extension View {
    /// 骨架态的呼吸光
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Theme.stroke.opacity(0.07), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .scaleEffect(x: 0.6, anchor: .center)
                .offset(x: phase * 320)
                .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}
