import SwiftUI

/// 根视图：打开即聊天，最近一次会话直接恢复；切会话走左侧抽屉
struct RootView: View {
    @EnvironmentObject private var client: AgentClient

    /// 当前展示的会话；草稿态没有服务端 ID
    @State private var current: ThreadSummary = .draft()
    /// 草稿发消息后落库的真实 ID，用于抽屉里高亮
    @State private var activeId: String?
    @State private var threads: [ThreadSummary] = []
    @State private var drawerOpen = false
    @State private var showSettings = false
    @State private var bootstrapped = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ChatView(
                    thread: current,
                    onOpenDrawer: { openDrawer() },
                    onThreadCreated: { id in
                        activeId = id
                        Task { await reloadThreads() }
                    }
                )
                .id(current.id)

                if drawerOpen {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { closeDrawer() }

                    ThreadDrawer(
                        threads: threads,
                        activeId: activeId,
                        onSelect: { thread in
                            current = thread
                            activeId = thread.id
                            closeDrawer()
                        },
                        onNew: {
                            current = .draft()
                            activeId = nil
                            closeDrawer()
                        },
                        onRename: { thread, name in
                            try? await client.renameThread(thread.id, title: name)
                            await reloadThreads()
                        },
                        onDelete: { thread in
                            try? await client.deleteThread(thread.id)
                            if activeId == thread.id {
                                current = .draft()
                                activeId = nil
                            }
                            await reloadThreads()
                        },
                        onSettings: {
                            closeDrawer()
                            showSettings = true
                        }
                    )
                    .frame(width: geo.size.width * 0.82)
                    .transition(.move(edge: .leading))
                }
            }
        }
        .task { await bootstrap() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.surface)
        }
    }

    // MARK: - 动作

    private func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await client.checkHealth()
        await reloadThreads()
        // 上次聊的那个排在最前，直接接着聊
        if let latest = threads.first {
            current = latest
            activeId = latest.id
        }
    }

    private func reloadThreads() async {
        threads = (try? await client.listThreads()) ?? []
        if let activeId, !threads.contains(where: { $0.id == activeId }) {
            self.activeId = nil
        }
    }

    private func openDrawer() {
        withAnimation(.easeOut(duration: 0.22)) { drawerOpen = true }
        Task { await reloadThreads() }
    }

    private func closeDrawer() {
        withAnimation(.easeIn(duration: 0.18)) { drawerOpen = false }
    }
}
