import AppKit
import SwiftUI

struct PhraseTipContent {
    let title: String
    let code: String?
    let detail: String
    let symbol: String
    let tint: Color
    let accessibilityText: String

    init(message: String, preview: Bool = false) {
        accessibilityText = preview ? "提示预览。\(message)" : message
        let lines = message.components(separatedBy: "\n")
        let first = lines.first ?? message
        let added = first.hasPrefix("已入库：")
        let known = first.hasPrefix("已有：")
        if added || known,
           let colon = first.firstIndex(of: "："),
           let arrow = first.range(of: " → ") {
            title = String(first[first.index(after: colon)..<arrow.lowerBound])
            code = String(first[arrow.upperBound...])
            let status = added ? "已入库" : "已有"
            let hint = lines.dropFirst().joined(separator: " ")
            detail = preview ? "提示预览 · 不会写入词库" : status + (hint.isEmpty ? "" : " · \(hint)")
            symbol = added ? "checkmark.circle.fill" : "checkmark.circle"
            tint = added ? Color(nsColor: .systemGreen) : .secondary
        } else {
            let failed = first.hasPrefix("未添加：")
            title = failed ? "未添加" : "自定义短语"
            code = nil
            detail = (preview ? "提示预览 · " : "") + (failed ? String(message.dropFirst(4)) : message)
            symbol = failed ? "exclamationmark.circle.fill" : "info.circle"
            tint = failed ? Color(nsColor: .systemOrange) : .secondary
        }
    }
}

/// The phrase and its code are the first scan line; the outcome and recovery
/// hint stay together below. Uses the same system typography as Settings.
struct PhraseTipView: View {
    let content: PhraseTipContent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: content.symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(content.tint)
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(content.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let code = content.code {
                        Spacer(minLength: 0)
                        Text(code)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize()
                    }
                }
                Text(content.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityText)
    }
}
