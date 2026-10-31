import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let onTapImage: (UIImage) -> Void

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            if let base64 = message.imageBase64,
               let picked = ImageCompressor.image(fromBase64: base64, cacheKey: message.id) {
                Image(uiImage: picked)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 220 * min(1.4, max(0.6, picked.size.height / max(picked.size.width, 1))))
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.stroke.opacity(0.08), lineWidth: 1)
                    )
                    .onTapGesture { onTapImage(picked) }
                    .accessibilityLabel("聊天截图")
            }

            if let text = message.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.isUser ? Color.white : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleBackground)
                    .overlay(bubbleBorder)
            }
        }
        .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accentGradient)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface)
        }
    }

    @ViewBuilder
    private var bubbleBorder: some View {
        if message.isUser {
            EmptyView()
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke.opacity(0.07), lineWidth: 1)
        }
    }
}
