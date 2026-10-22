import AppKit
import KimBiseoCore

/// 첨부 이미지를 Claude 에 보내기 좋은 크기로 줄이고, 화면 표시용으로 앱 데이터 폴더에 저장한다.
enum ImageLoader {
    static let maxSide: CGFloat = 1568       // Claude 권장 최대 변 길이
    static let maxCount = 5

    static var folder: URL { AppPaths.dataDir.appendingPathComponent("attachments", isDirectory: true) }

    static func load(url: URL) -> ImageAttachment? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return attachment(from: image)
    }

    static func attachment(from image: NSImage) -> ImageAttachment? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSImage(cgImage: cg, size: NSSize(width: w, height: h)).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: file)
        return ImageAttachment(mediaType: "image/jpeg", data: data, path: file.path)
    }

    /// 클립보드에 이미지(스크린샷 데이터 또는 이미지 파일)가 있는지.
    static func pasteboardHasImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) {
            return true
        }
        let types = pasteboard.types ?? []
        let hasImageData = types.contains(.png) || types.contains(.tiff) || types.contains(NSPasteboard.PasteboardType("public.jpeg"))
        return hasImageData && !types.contains(.string)
    }

    /// 클립보드의 이미지 (스크린샷 붙여넣기).
    static func fromPasteboard(_ pasteboard: NSPasteboard = .general) -> [ImageAttachment] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           !urls.isEmpty {
            return urls.compactMap(load(url:))
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] {
            return images.compactMap(attachment(from:))
        }
        return []
    }

    static func chooseFiles() -> [ImageAttachment] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "첨부할 이미지를 고르세요"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(load(url:))
    }
}
