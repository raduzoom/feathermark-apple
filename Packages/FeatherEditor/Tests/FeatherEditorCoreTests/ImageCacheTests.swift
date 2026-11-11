import FeatherEditorTestSupport
import Foundation
import Testing
@testable import FeatherEditorCore

/// The attachment image cache (moved to the core in Phase 13, so it runs on iOS too).
@MainActor @Suite struct ImageCacheTests {
    func load(_ cache: ImageCache, _ url: URL) async {
        var done = false
        cache.load(url) { done = true }
        _ = await waitFor({ done }, timeout: 15)
    }

    @Test func cacheEvictsLeastRecentlyUsed() async {
        let cache = ImageCache(limit: 2)
        let a = makePNG(width: 8, height: 8), b = makePNG(width: 9, height: 9), c = makePNG(width: 10, height: 10)
        await load(cache, a)
        await load(cache, b)
        _ = cache.image(for: a)   // a is used again, so b is now the oldest
        await load(cache, c)
        #expect(cache.image(for: a) != nil)
        #expect(cache.image(for: b) == nil)
        #expect(cache.image(for: c) != nil)
    }

    @Test func failedFileRetriesAfterForget() async throws {
        let cache = ImageCache()
        let url = FileManager.default.temporaryDirectory.appending(path: "FN-\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: url)
        await load(cache, url)
        #expect(cache.hasFailed(url))
        try Data(contentsOf: makePNG(width: 4, height: 4)).write(to: url)
        cache.forgetFailure(for: url)
        await load(cache, url)
        #expect(cache.image(for: url) != nil)
    }

    @Test func imageKeepsItsPixelSizeInPoints() async {
        let cache = ImageCache()
        let url = makePNG(width: 300, height: 120)
        await load(cache, url)
        #expect(cache.image(for: url)?.size == CGSize(width: 300, height: 120))
    }
}
