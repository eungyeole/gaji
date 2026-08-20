import AppKit
import SwiftUI

struct CodeTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              context.coordinator.renderedText != text else { return }
        context.coordinator.renderedText = text
        textView.textStorage?.setAttributedString(render(text))
        textView.scrollToBeginningOfDocument(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderedText = ""
    }

    private func render(_ patch: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let result = NSMutableAttributedString(string: "")
        var oldLine: Int?
        var newLine: Int?

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let kind = lineKind(line)
            if kind == .hunk {
                (oldLine, newLine) = hunkLines(line)
            }
            let oldNumber: Int?
            let newNumber: Int?
            switch kind {
            case .addition:
                oldNumber = nil; newNumber = newLine; newLine = newLine.map { $0 + 1 }
            case .deletion:
                oldNumber = oldLine; newNumber = nil; oldLine = oldLine.map { $0 + 1 }
            case .context:
                oldNumber = oldLine; newNumber = newLine
                oldLine = oldLine.map { $0 + 1 }; newLine = newLine.map { $0 + 1 }
            default:
                oldNumber = nil; newNumber = nil
            }

            let prefix = "\(number(oldNumber)) \(number(newNumber)) │ "
            let renderedLine = NSMutableAttributedString(string: prefix + line + "\n", attributes: base)
            renderedLine.addAttribute(
                .foregroundColor,
                value: NSColor.tertiaryLabelColor,
                range: NSRange(location: 0, length: (prefix as NSString).length)
            )
            let wholeLine = NSRange(location: 0, length: renderedLine.length)
            switch kind {
            case .addition:
                renderedLine.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.14), range: wholeLine)
            case .deletion:
                renderedLine.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.14), range: wholeLine)
            case .hunk:
                renderedLine.addAttributes([
                    .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.14),
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
                ], range: wholeLine)
            case .metadata:
                renderedLine.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: wholeLine)
            case .context:
                break
            }
            result.append(renderedLine)
        }
        return result
    }

    private enum LineKind: Equatable { case metadata, hunk, addition, deletion, context }

    private func lineKind(_ line: String) -> LineKind {
        if line.hasPrefix("@@") { return .hunk }
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .addition }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .deletion }
        if line.hasPrefix(" ") { return .context }
        return .metadata
    }

    private func hunkLines(_ header: String) -> (Int?, Int?) {
        let parts = header.split(separator: " ")
        return (lineStart(parts.first { $0.hasPrefix("-") }), lineStart(parts.first { $0.hasPrefix("+") }))
    }

    private func lineStart(_ value: Substring?) -> Int? {
        guard let value else { return nil }
        return Int(value.dropFirst().split(separator: ",", maxSplits: 1).first ?? "")
    }

    private func number(_ value: Int?) -> String {
        value.map { String(format: "%5d", $0) } ?? "     "
    }
}
