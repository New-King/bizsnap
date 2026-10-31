import SwiftUI

struct Composer: View {
    @Binding var text: String
    @Binding var image: UIImage?
    let sending: Bool
    let onSend: () -> Void
    let onPickPhoto: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !sending && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil)
    }

    private var showClear: Bool {
        focused || !text.isEmpty || image != nil
    }

    /// 清空本轮输入并收起键盘
    private func clear() {
        text = ""
        image = nil
        focused = false
    }

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                self.image = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("移除截图")
                        }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // 整条输入栏是一个容器：左图标、中文本、右发送，不再拆成三个方块
            HStack(alignment: .bottom, spacing: 4) {
                Button(action: onPickPhoto) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("从相册选截图")

                TextField("说点什么，或贴一张聊天截图", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    // TextField 默认只有文字那一行吃点击，这里把整块矩形（含上下留白）都算作热区
                    .contentShape(Rectangle())
                    .focused($focused)

                if showClear {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 28, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("清空并收起键盘")
                }

                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(canSend ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
                            .frame(width: 32, height: 32)
                        if sending {
                            ProgressView().tint(Theme.textTertiary)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(canSend ? Color.white : Theme.textTertiary)
                        }
                    }
                    .padding(.bottom, 3)
                }
                .disabled(!canSend)
                .accessibilityLabel("发送")
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            // 整条输入栏里的空白处也响应点击，子按钮（相册 / 清空 / 发送）仍优先
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { focused = true }
            .composerBackground()
            // 聚焦不加 outline：内 1px 亮环 + 外 3px 淡环，做出「咬合」的层次
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(focused ? 0.35 : 0), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.accent.opacity(focused ? 0.10 : 0), lineWidth: 3)
            )
            .animation(.easeOut(duration: 0.18), value: focused)
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        // 背景铺到屏幕底部，避免安全区下露出一条色带
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }
}

private extension View {
    /// iOS 26 用系统的 Liquid Glass，低版本退回实色底
    @ViewBuilder
    func composerBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.elevated)
            )
        }
    }
}
