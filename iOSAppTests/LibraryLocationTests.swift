import Foundation
import Testing
@testable import FeatherMarkiOS

@Suite struct LibraryLocationTests {
    let support = URL(fileURLWithPath: "/tmp/FNSupport-\(UUID().uuidString)", isDirectory: true)
    let tmp = URL(fileURLWithPath: "/tmp/FNTmp-\(UUID().uuidString)", isDirectory: true)

    func directory(_ arguments: [String], _ environment: [String: String] = [:]) -> URL {
        LibraryLocation.directory(arguments: arguments, environment: environment, supportDirectory: support, temporaryDirectory: tmp)
    }

    @Test func overrideArgumentWins() {
        #expect(directory(["app", "-FeatherLibraryPath", "/tmp/given", "-FeatherTemporaryLibrary"]).path == "/tmp/given")
    }

    @Test func temporaryLibraryArgumentUsesTmp() {
        let a = directory(["app", "-FeatherTemporaryLibrary"])
        let b = directory(["app", "-FeatherTemporaryLibrary"])
        #expect(a.path.hasPrefix(tmp.path + "/FeatherMark-UITest-"))
        #expect(a != b)
    }

    @Test func testHostUsesTemporaryLibrary() {
        let d = directory(["app"], ["XCTestConfigurationFilePath": "/x"])
        #expect(d.path.hasPrefix(tmp.path + "/FeatherMark-TestHost-"))
    }

    @Test func defaultIsApplicationSupportFeatherMark() {
        #expect(directory(["app"]) == support.appending(path: "FeatherMark", directoryHint: .isDirectory))
        #expect(!LibraryLocation.isIsolated(arguments: ["app"], environment: [:]))
    }

    @Test func isolatedRunsNeverUseTheRealLibrary() {
        let cases: [([String], [String: String])] = [
            (["app", "-FeatherLibraryPath", "/tmp/given"], [:]),
            (["app", "-FeatherTemporaryLibrary"], [:]),
            (["app"], ["XCTestBundlePath": "/x"]),
        ]
        for (arguments, environment) in cases {
            #expect(!directory(arguments, environment).path.hasPrefix(support.path), "\(arguments)")
            #expect(LibraryLocation.isIsolated(arguments: arguments, environment: environment), "\(arguments)")
        }
    }

    @Test func prepareCreatesFolderWithProtection() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FNPrepare-\(UUID().uuidString)", directoryHint: .isDirectory)
        try LibraryLocation.prepare(dir)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue)
        let protection = try FileManager.default.attributesOfItem(atPath: dir.path)[.protectionKey] as? FileProtectionType
        if protection == nil {
            withKnownIssue("The simulator reports no file protection; the device run checks it") {
                #expect(protection == .completeUntilFirstUserAuthentication)
            }
        } else {
            #expect(protection == .completeUntilFirstUserAuthentication)
        }
    }
}
