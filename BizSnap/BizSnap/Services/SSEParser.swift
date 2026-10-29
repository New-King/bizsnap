import Foundation

/// 一行 `data: {...}` 解成一个事件。
/// 注释帧（`: heartbeat`）、空行、以及不认识的行一律忽略——心跳只为了不让中间层掐连接。
enum SSEParser {
    private static let prefix = "data:"

    static func event(from line: String, decoder: JSONDecoder) -> StreamEvent? {
        guard line.hasPrefix(prefix) else { return nil }
        let payload = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        guard let raw = try? decoder.decode(RawStreamEvent.self, from: data) else { return nil }
        return raw.toEvent()
    }
}
