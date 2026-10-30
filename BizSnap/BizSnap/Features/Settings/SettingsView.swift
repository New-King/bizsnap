import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var client: AgentClient
    @Environment(\.dismiss) private var dismiss

    @State private var serverText = ""
    @State private var busy = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        serverCard
                        actionCard
                        noteCard
                        if let message {
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundStyle(messageIsError ? Theme.red : Theme.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.accentSoft)
                }
            }
        }
        .onAppear { serverText = client.serverText }
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("服务地址")
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:8787", text: $serverText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.elevated))

                Button("保存") {
                    client.updateServer(serverText)
                    Task { await refreshHealth() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.9)))
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(client.online ? Theme.green : Theme.textTertiary)
                    .frame(width: 7, height: 7)
                Text(client.online ? "已连接" : "未连接")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            // 真机上 127.0.0.1 指向手机自身，必须换成 Mac 的局域网地址
            Text("模拟器用 http://127.0.0.1:8787；真机填 Mac 的局域网地址，如 http://192.168.1.5:8787")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard(padding: 16)
    }

    private var actionCard: some View {
        VStack(spacing: 0) {
            actionRow(
                title: "清空全部数据",
                detail: "服务端联系人、事件与会话，连同本应用写入系统通讯录、日历的内容一起删除",
                destructive: true
            ) {
                do {
                    // 服务端先清，并把名单带回来，系统侧照着删
                    let summary = try await client.resetServerData()
                    let contacts = (try? ContactsService.shared.deleteCreated(names: summary.createdNames)) ?? 0
                    let events = CalendarService.shared.deleteCreated(titles: summary.meetingTitles)
                    SystemWriteLog.clear()
                    show("已清空：联系人 \(contacts) 位、会议 \(events) 场", isError: false)
                } catch {
                    show(error.localizedDescription, isError: true)
                }
            }
        }
        .glassCard(padding: 0)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("说明")
            Text("通讯录只能承载姓名、电话、邮箱、公司与职位。行业、项目、关系仅本应用可见。会议写入系统日历，需要日历权限。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func actionRow(
        title: String,
        detail: String,
        destructive: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                await action()
                busy = false
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(destructive ? Theme.red : Theme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView().tint(Theme.accentSoft)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
    }

    private func refreshHealth() async {
        await client.checkHealth()
    }

    private func show(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }
}
