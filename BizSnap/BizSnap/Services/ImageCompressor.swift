import UIKit

enum ImageCompressor {
    /// 官方规则（api-docs.deepseek.com/zh-cn/guides/vision）：每张图进模型前会被等比缩到
    /// 「总像素约 1300×1300」，每图 token 封顶 1024。本地按同一总像素压即可：
    /// 既不糊，也不白传像素；再长的截图，模型看到的同样是这个上限。
    static func jpegBase64(_ image: UIImage, maxPixels: CGFloat = 1300 * 1300, quality: CGFloat = 0.7) -> String? {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return nil }
        let scale = width * height > maxPixels ? sqrt(maxPixels / (width * height)) : 1
        let target = CGSize(width: width * scale, height: height * scale)
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
