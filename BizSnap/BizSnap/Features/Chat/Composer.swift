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
        VStack(spacing: 8) {
            if let image {
                HStack(spacing: 8) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                self.image = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("移除截图")
                        }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
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
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.elevated))
                }
                .accessibilityLabel("添加截图")

                TextField("说点什么，或贴一张聊天截图", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            )
                    )

                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(canSend ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.elevated))
                            .frame(width: 38, height: 38)
                        if sending {
                            ProgressView().tint(Theme.textSecondary)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(canSend ? .white : Theme.textTertiary)
                        }
                    }
                }
                .disabled(!canSend)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 8)
        }
        .background(Theme.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
        }
    }
}
