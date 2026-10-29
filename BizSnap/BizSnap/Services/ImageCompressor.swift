import UIKit

enum ImageCompressor {
    /// 截图压到最长边 1280、质量 0.7：够模型读文字，又不至于让请求体过大
    static func jpegBase64(_ image: UIImage, maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> String? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }

    static func image(fromBase64 base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}
