import SwiftUI

struct Composer: View {
    @Binding var text: String
    @Binding var image: UIImage?
    let sending: Bool
    let onSend: () -> Void
    let onPickPhoto: () -> Void
    let onCamera: () -> Void

    private var canSend: Bool {
        !sending && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil)
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
                Menu {
                    Button {
                        onPickPhoto()
                    } label: {
                        Label("从相册选", systemImage: "photo")
                    }
                    Button {
                        onCamera()
                    } label: {
                        Label("拍一张", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("添加截图")

                TextField("说点什么，或贴一张聊天截图", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 9)
                    .frame(minHeight: 36, alignment: .leading)

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
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.elevated)
            )
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        // 背景铺到屏幕底部，避免安全区下露出一条色带
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }
}
