import FeatherEditorCore
import Foundation
import Testing
import UIKit
@testable import FeatherMarkiOS

@MainActor @Suite struct ReaderTests {
    let body = """
        Goal: reliable readings **through winter**.

        ## Parts

        - Raspberry Pi Zero 2 W
        - [x] Order the sensor

        > Mount it two metres up.

        ```swift
        let celsius = Double(raw) / 100
        ```
        """

    func reader() -> ReaderUITextView {
        let view = ReaderUITextView(images: ReaderImages(resolve: { _ in nil }, maxWidth: 560))
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        view.show(body)
        view.layoutIfNeeded()
        return view
    }

    @Test func readerShowsExactMarkdown() {
        let view = reader()
        #expect(view.textStorage.string == body)
        #expect(!view.isEditable && view.isSelectable)
        #expect(view.textLayoutManager != nil)   // still TextKit 2 after layout
    }

    @Test func everyParagraphIsDecorated() throws {
        let view = reader()
        let manager = try #require(view.textLayoutManager)
        var fragments: [NSTextLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            fragments.append($0)
            return true
        }
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0 is DecoratedLayoutFragment })
    }

    @Test func imageHeightFollowsTheMacRule() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FNReader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func png(_ name: String, _ w: CGFloat, _ h: CGFloat) throws -> URL {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let data = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).pngData { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
            let url = dir.appending(path: name)
            try data.write(to: url)
            return url
        }
        let wide = try png("wide.png", 1200, 600)
        let small = try png("small.png", 200, 100)
        let files = ["feather://attachment/wide": wide, "feather://attachment/small": small]
        let images = ReaderImages(resolve: { files[$0] }, maxWidth: 560)
        #expect(images.height(for: "feather://attachment/wide") == 280)
        #expect(images.height(for: "feather://attachment/small") == 100)
        #expect(images.height(for: "feather://attachment/missing") == 96)
        #expect(images.image(for: "feather://attachment/wide") != nil)
        #expect(images.image(for: "feather://attachment/missing") == nil)
    }
}
