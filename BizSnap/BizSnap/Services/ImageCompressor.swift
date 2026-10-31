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

    /// 解码结果按 key 缓存。气泡的 body 每次状态变化都会重算，一张 600KB 的截图若每次都重新解码，
    /// 勾选、切 loading 这类动作都会先卡一下主线程。
    private static let decoded = NSCache<NSString, UIImage>()

    static func image(fromBase64 base64: String, cacheKey: String? = nil) -> UIImage? {
        if let cacheKey, let cached = decoded.object(forKey: cacheKey as NSString) {
            return cached
        }
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return nil }
        if let cacheKey {
            decoded.setObject(image, forKey: cacheKey as NSString)
        }
        return image
    }
}
