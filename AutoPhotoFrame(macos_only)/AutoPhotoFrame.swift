import AppKit
import Foundation

struct FrameStyle { let side: CGFloat; let top: CGFloat; let bottom: CGFloat; let typeSize: CGFloat }

func style(for size: NSSize) -> FrameStyle {
    let r = size.width / size.height, s = min(size.width, size.height)
    if r < 0.86 { return .init(side: s * 0.09, top: s * 0.09, bottom: s * 0.305, typeSize: s * 0.027) }
    if r > 1.35 { return .init(side: s * 0.075, top: s * 0.075, bottom: s * 0.245, typeSize: s * 0.025) }
    return .init(side: s * 0.10, top: s * 0.10, bottom: s * 0.315, typeSize: s * 0.028)
}

func nextOutputURL(for input: URL) -> URL {
    let parent = input.deletingLastPathComponent(), stem = input.deletingPathExtension().lastPathComponent
    var count = 1
    while true {
        let suffix = count == 1 ? " — framed.jpg" : " — framed \(count).jpg"
        let result = parent.appendingPathComponent(stem + suffix)
        if !FileManager.default.fileExists(atPath: result.path) { return result }
        count += 1
    }
}

func render(_ input: URL, title: String) throws -> URL {
    guard let original = NSImage(contentsOf: input), original.size.width > 0, original.size.height > 0 else {
        throw NSError(domain: "Frame", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取 \(input.lastPathComponent)"])
    }
    let size = original.size, frame = style(for: size)
    let canvasSize = NSSize(width: size.width + frame.side * 2, height: size.height + frame.top + frame.bottom)
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()
    NSColor(calibratedRed: 0.965, green: 0.958, blue: 0.940, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    original.draw(in: NSRect(x: frame.side, y: frame.bottom, width: size.width, height: size.height), from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    let fontSize = max(11, frame.typeSize)
    let font = NSFont(name: "Baskerville", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 0.82), .paragraphStyle: paragraph, .kern: max(0.15, fontSize * 0.035)]
    (title as NSString).draw(in: NSRect(x: frame.side, y: frame.bottom * 0.37, width: size.width, height: frame.bottom * 0.35), withAttributes: attributes)
    // Finish the AppKit drawing context before asking NSImage for pixel data.
    canvas.unlockFocus()
    guard let data = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.94]) else {
        throw NSError(domain: "Frame", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法导出 JPEG"])
    }
    let result = nextOutputURL(for: input); try jpeg.write(to: result, options: .atomic); return result
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var receivedFiles = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.receivedFiles else { return }
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
            if panel.runModal() == .OK { self.process(panel.urls) } else { NSApp.terminate(nil) }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) { receivedFiles = true; process(urls) }
    private func process(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Humanist Photography Frame"; alert.informativeText = "为作品输入标题（可留空）"
        let field = NSTextField(string: ""); field.frame.size.width = 320; alert.accessoryView = field; alert.addButton(withTitle: "生成") ; alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
        var saved: [URL] = []; var failures: [String] = []
        for url in urls { do { saved.append(try render(url, title: field.stringValue)) } catch { failures.append(error.localizedDescription) } }
        if !saved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(saved) }
        let done = NSAlert(); done.messageText = failures.isEmpty ? "已生成" : "部分文件未生成"; done.informativeText = failures.isEmpty ? "最终 JPEG 已保存到原图所在文件夹。" : failures.joined(separator: "\n"); done.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
