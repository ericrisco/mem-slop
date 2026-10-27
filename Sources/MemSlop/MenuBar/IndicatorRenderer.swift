import AppKit

/// Draws the menu bar indicator as a template image (monochrome, adapts to light/dark menu bars).
/// Plain AppKit drawing: it runs every refresh, so it must stay cheap.
enum IndicatorRenderer {
    struct Values: Equatable {
        var style: DisplayStyle
        var cpu: Int
        var memory: Int

        init(style: DisplayStyle, cpu: Double, memory: Double) {
            self.style = style
            self.cpu = Int((cpu * 100).rounded())
            self.memory = Int((memory * 100).rounded())
        }
    }

    private static let height: CGFloat = 22

    static func image(for values: Values) -> NSImage {
        let image: NSImage
        switch values.style {
        case .text:
            image = row([(symbol: "cpu", value: values.cpu), (symbol: "memorychip", value: values.memory)])
        case .cpu:
            image = row([(symbol: "cpu", value: values.cpu)])
        case .memory:
            image = row([(symbol: "memorychip", value: values.memory)])
        case .compact:
            image = compact(cpu: values.cpu, memory: values.memory)
        case .bars:
            image = bars(cpu: values.cpu, memory: values.memory)
        case .icon:
            image = symbol("memorychip", size: 14, weight: .medium).map { icon in
                draw(width: icon.size.width) { _ in
                    icon.draw(at: NSPoint(x: 0, y: (height - icon.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                }
            } ?? NSImage()
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Styles

    private static func row(_ items: [(symbol: String, value: Int)]) -> NSImage {
        let font = roundedDigits(size: 12.5, weight: .semibold)
        let valueWidth = ceil(("100%" as NSString).size(withAttributes: [.font: font]).width)
        let icons = items.map { symbol($0.symbol, size: 11, weight: .semibold) }
        let iconWidth = icons.map { $0?.size.width ?? 0 }.max() ?? 0
        let itemWidth = iconWidth + 3 + valueWidth
        let gap: CGFloat = 7
        let width = itemWidth * CGFloat(items.count) + gap * CGFloat(items.count - 1)
        return draw(width: width) { _ in
            var x: CGFloat = 0
            for (index, item) in items.enumerated() {
                if let icon = icons[index] {
                    icon.draw(at: NSPoint(x: x + (iconWidth - icon.size.width) / 2, y: (height - icon.size.height) / 2),
                              from: .zero, operation: .sourceOver, fraction: 1)
                }
                drawText("\(item.value)%", font: font, in: NSRect(x: x + iconWidth + 3, y: 0, width: valueWidth, height: height), align: .right)
                x += itemWidth + gap
            }
        }
    }

    private static func compact(cpu: Int, memory: Int) -> NSImage {
        let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
        let valueFont = roundedDigits(size: 9.5, weight: .bold)
        let labelWidth = ceil(("RAM" as NSString).size(withAttributes: [.font: labelFont]).width)
        let valueWidth = ceil(("100%" as NSString).size(withAttributes: [.font: valueFont]).width)
        let width = labelWidth + 3 + valueWidth
        return draw(width: width) { _ in
            for (line, (label, value)) in [("CPU", cpu), ("RAM", memory)].enumerated() {
                let y: CGFloat = line == 0 ? 10.5 : 0.5
                drawText(label, font: labelFont, in: NSRect(x: 0, y: y - 0.5, width: labelWidth, height: 11), align: .left)
                drawText("\(value)%", font: valueFont, in: NSRect(x: labelWidth + 3, y: y, width: valueWidth, height: 11), align: .right)
            }
        }
    }

    private static func bars(cpu: Int, memory: Int) -> NSImage {
        let labelFont = NSFont.systemFont(ofSize: 6, weight: .heavy)
        let barWidth: CGFloat = 6, barHeight: CGFloat = 13, gap: CGFloat = 3
        return draw(width: barWidth * 2 + gap) { _ in
            for (index, (label, value)) in [("C", cpu), ("M", memory)].enumerated() {
                let x = CGFloat(index) * (barWidth + gap)
                let frame = NSRect(x: x + 0.5, y: 7.5, width: barWidth - 1, height: barHeight)
                let outline = NSBezierPath(roundedRect: frame, xRadius: 1.5, yRadius: 1.5)
                NSColor.black.withAlphaComponent(0.55).setStroke()
                outline.lineWidth = 1
                outline.stroke()
                let fillHeight = max(1.5, barHeight * CGFloat(min(100, value)) / 100)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: fillHeight),
                             xRadius: 1.5, yRadius: 1.5).fill()
                drawText(label, font: labelFont, in: NSRect(x: x - 1, y: -0.5, width: barWidth + 2, height: 8), align: .center)
            }
        }
    }

    // MARK: - Helpers

    private static func draw(width: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { rect in
            body(rect)
            return true
        }
    }

    private static func drawText(_ text: String, font: NSFont, in rect: NSRect, align: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let y = rect.minY + (rect.height - size.height) / 2
        (text as NSString).draw(in: NSRect(x: rect.minX, y: y, width: rect.width, height: size.height), withAttributes: attributes)
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    private static func roundedDigits(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }
}
