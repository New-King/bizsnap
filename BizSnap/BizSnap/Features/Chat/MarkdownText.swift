import SwiftUI

/// 渲染模型回答里的轻量 Markdown：粗体、斜体、行内代码、标题、无序/有序列表、表格。
/// 表格 AttributedString 不支持，用 SwiftUI 自己排。
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 渲染

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .paragraph(let content):
            Text(Self.inline(content))
                .font(.system(size: 15))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let content, let level):
            Text(Self.inline(content))
                .font(.system(size: level <= 2 ? 16 : 15, weight: .semibold))
                .padding(.top, 2)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(Self.inline(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 15))
                }
            }

        case .table(let rows):
            table(rows)

        case .code(let content):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(size: 13, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// 每列按内容宽度排，放不下就横向滑动 —— 挤成等宽会把公司名、职位折成两行
    private func table(_ rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(Self.inline(cell))
                                .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 44, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Theme.stroke.opacity(0.12))
                            .frame(height: 1)
                    }
                }
            }
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        // 横向滚动默认会吃掉高度，这里让它按内容高度撑开
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 行内

    static func inline(_ string: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }

    // MARK: - 分块

    enum Block {
        case paragraph(String)
        case heading(String, Int)
        case bullets([String])
        case table([[String]])
        case code(String)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var table: [[String]] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            let content = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { blocks.append(.paragraph(content)) }
            paragraph.removeAll()
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            bullets.removeAll()
        }
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table)) }
            table.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushTable()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code.removeAll()
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushAll()
                continue
            }

            if line.hasPrefix("|"), line.contains("|") {
                flushParagraph()
                flushBullets()
                let cells = line
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let trimmed = cells.first?.isEmpty == true ? Array(cells.dropFirst()) : cells
                let final = trimmed.last?.isEmpty == true ? Array(trimmed.dropLast()) : trimmed
                // 分隔行 |---|---| 不进表格
                let isSeparator = !final.isEmpty && final.allSatisfy { cell in
                    cell.range(of: "^:?-{2,}:?$", options: .regularExpression) != nil
                }
                if !isSeparator { table.append(final) }
                continue
            }

            if line.hasPrefix("#") {
                flushAll()
                let level = line.prefix(while: { $0 == "#" }).count
                let content = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { blocks.append(.heading(content, level)) }
                continue
            }

            if let bullet = bulletContent(of: line) {
                flushParagraph()
                flushTable()
                bullets.append(bullet)
                continue
            }

            flushBullets()
            flushTable()
            paragraph.append(line)
        }

        if inCode, !code.isEmpty { blocks.append(.code(code.joined(separator: "\n"))) }
        flushAll()
        return blocks
    }

    /// 「- 」「* 」「1. 」都算列表项
    private static func bulletContent(of line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        if let match = line.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
            return String(line[match.upperBound...])
        }
        return nil
    }
}
