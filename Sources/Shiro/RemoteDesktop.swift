import AppKit
import SwiftUI
import ShiroCore

struct RemoteDesktop: NSViewRepresentable {
    var image: NSImage?
    var enabled: Bool
    var send: ([String: JSON]) -> Void
    func makeNSView(context: Context) -> DesktopSurface { let view = DesktopSurface(); view.setAccessibilityElement(true); view.setAccessibilityRole(.button); view.setAccessibilityLabel("Live computer screen"); return view }
    func updateNSView(_ view: DesktopSurface, context: Context) { view.image = image; view.inputEnabled = enabled; view.send = send; view.needsDisplay = true }
}

final class DesktopSurface: NSView, NSTextInputClient {
    var image: NSImage?
    var inputEnabled = false
    var send: ([String: JSON]) -> Void = { _ in }
    private var down: NSPoint?
    private var composition: NSAttributedString?
    private var compositionSelection = NSRange(location: 0, length: 0)
    private var bufferedText = ""
    private var textFlush: DispatchWorkItem?
    private func flushText() { textFlush?.cancel(); textFlush = nil; guard !bufferedText.isEmpty else { return }; let text = bufferedText; bufferedText = ""; send(["action": .string("type"), "text": .string(text)]) }
    override var acceptsFirstResponder: Bool { inputEnabled }
    override func accessibilityPerformPress() -> Bool { guard inputEnabled else { return false }; window?.makeFirstResponder(self); return true }
    override var isFlipped: Bool { true }
    private var imageRect: NSRect {
        let width = min(bounds.width, bounds.height * 1.6), height = min(bounds.height, bounds.width / 1.6)
        return NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        image?.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    private func point(_ event: NSEvent) -> NSPoint? {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard inputEnabled, r.contains(p), r.width > 0 else { return nil }
        return NSPoint(x: floor((p.x-r.minX)/r.width*1280), y: floor((p.y-r.minY)/r.height*800))
    }
    override func mouseDown(with event: NSEvent) { guard let p = point(event) else { return }; window?.makeFirstResponder(self); down = p }
    override func mouseUp(with event: NSEvent) {
        guard let p = point(event), let start = down else { return }; down = nil
        if hypot(p.x-start.x, p.y-start.y) > 5 { send(["action": .string("drag"), "x": .number(start.x), "y": .number(start.y), "x2": .number(p.x), "y2": .number(p.y)]) }
        else { send(["action": .string("click"), "x": .number(p.x), "y": .number(p.y)]) }
    }
    override func rightMouseDown(with event: NSEvent) { guard let p = point(event) else { return }; window?.makeFirstResponder(self); send(["action": .string("click"), "x": .number(p.x), "y": .number(p.y), "button": .number(3)]) }
    override func scrollWheel(with event: NSEvent) { guard point(event) != nil, abs(event.scrollingDeltaY) > 0.1 else { return }; send(["action": .string("scroll"), "direction": .string(event.scrollingDeltaY > 0 ? "up" : "down")]) }
    @objc func paste(_ sender: Any?) { guard inputEnabled else { return }; flushText(); if let text = NSPasteboard.general.string(forType: .string) { send(["action": .string("type"), "text": .string(text)]) } }
    override func keyDown(with event: NSEvent) {
        guard inputEnabled else { return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            flushText()
            if let text = NSPasteboard.general.string(forType: .string) { send(["action": .string("type"), "text": .string(text)]) }
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { flushText(); send(["action": .string("copy")]); return }
        let special: [UInt16: String] = [36:"Return",48:"Tab",51:"BackSpace",53:"Escape",117:"Delete",123:"Left",124:"Right",125:"Down",126:"Up",115:"Home",119:"End",116:"Prior",121:"Next"]
        var mods: [String] = []
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { mods.append("ctrl") }
        if event.modifierFlags.contains(.option) { mods.append("alt") }
        if event.modifierFlags.contains(.shift), special[event.keyCode] != nil || !mods.isEmpty { mods.append("shift") }
        if let key = special[event.keyCode] { flushText(); send(["action": .string("key"), "text": .string((mods+[key]).joined(separator: "+"))]) }
        else if !mods.isEmpty, let key = event.charactersIgnoringModifiers, !key.isEmpty { flushText(); send(["action": .string("key"), "text": .string((mods+[key]).joined(separator: "+"))]) }
        else { interpretKeyEvents([event]) }
    }
    override func insertText(_ insertString: Any) {
        guard inputEnabled else { return }
        let text = (insertString as? NSAttributedString)?.string ?? insertString as? String ?? ""
        if !text.isEmpty {
            bufferedText += text; textFlush?.cancel()
            let flush = DispatchWorkItem { [weak self] in self?.flushText() }
            textFlush = flush; DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: flush)
        }
    }
}

extension DesktopSurface {
    func insertText(_ string: Any, replacementRange: NSRange) { composition = nil; insertText(string) }
    func hasMarkedText() -> Bool { (composition?.length ?? 0) > 0 }
    func markedRange() -> NSRange { hasMarkedText() ? NSRange(location: 0, length: composition!.length) : NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { compositionSelection }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) { composition = string as? NSAttributedString ?? NSAttributedString(string: string as? String ?? ""); compositionSelection = selectedRange }
    func unmarkText() { composition = nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    func characterIndex(for point: NSPoint) -> Int { 0 }
}
