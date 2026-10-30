import SwiftUI

/// 左侧抽屉：搜索、新建、切换、改名、删除、进设置
struct ThreadDrawer: View {
    let threads: [ThreadSummary]
    let activeId: String?

    var onSelect: (ThreadSummary) -> Void
    var onNew: () -> Void
    var onRename: (ThreadSummary, String) async -> Void
    var onDelete: (ThreadSummary) async -> Void
    var onSettings: () -> Void

    @State private var query = ""
    @State private var renaming: ThreadSummary?
    @State private var renameText = ""

    private var filtered: [ThreadSummary] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return threads }
        return threads.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(keyword)
                || $0.lastMessage.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke.opacity(0.06))
            list
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.stroke.opacity(0.08)).frame(width: 0.5)
        }
        .alert("重命名对话", isPresented: renameBinding) {
            TextField("对话名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                guard let target = renaming else { return }
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renaming = nil
                guard !name.isEmpty else { return }
                Task { await onRename(target, name) }
            }
        }
    }

    // MARK: - 结构

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("搜索", text: $query)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.elevated.opacity(0.9))
            )

            Button(action: onNew) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("新建对话")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { thread in
                    row(thread)
                }
                if filtered.isEmpty {
                    Text(query.isEmpty ? "还没有对话" : "没有匹配的对话")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.stroke.opacity(0.06))
            HStack(spacing: 10) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("设置")

                Text("BizSnap")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func row(_ thread: ThreadSummary) -> some View {
        Button {
            onSelect(thread)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14))
                    Text(thread.avatarText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentSoft)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !thread.lastMessage.isEmpty {
                        Text(thread.lastMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(thread.id == activeId ? Theme.accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
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
                Task { await onDelete(thread) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }
}
