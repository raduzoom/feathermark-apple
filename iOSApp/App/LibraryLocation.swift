import Foundation

/// Where the one library of this install lives: `Application Support/FeatherMark` (design spec "Local storage";
/// iPhone spec "The library lives in the app's Application Support").
enum LibraryLocation {
    /// Tests only: open this library folder.
    static let overrideArgument = "-FeatherLibraryPath"
    /// UI tests only: open a fresh library in the app's own temporary folder.
    static let temporaryArgument = "-FeatherTemporaryLibrary"
    static let name = "FeatherMark"

    /// A test or UI-test run, which must never open the real library or settings.
    static func isIsolated(arguments: [String] = CommandLine.arguments,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        arguments.contains(overrideArgument) || arguments.contains(temporaryArgument) || isTestHost(environment)
    }

    static func directory(arguments: [String] = CommandLine.arguments,
                          environment: [String: String] = ProcessInfo.processInfo.environment,
                          fileManager: FileManager = .default,
                          supportDirectory: URL? = nil,
                          temporaryDirectory: URL? = nil) -> URL {
        let tmp = temporaryDirectory ?? fileManager.temporaryDirectory
        if let i = arguments.firstIndex(of: overrideArgument), i + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        }
        if arguments.contains(temporaryArgument) {
            return tmp.appending(path: "FeatherMark-UITest-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        // A unit-test run launches the app as its host: never let it open the person's real library.
        if isTestHost(environment) {
            return tmp.appending(path: "FeatherMark-TestHost-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        let support = supportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: name, directoryHint: .isDirectory)
    }

    /// Creates the folder with "complete until first user authentication" protection, so a save can finish if
    /// the phone locks mid-write; files created inside inherit it.
    static func prepare(_ directory: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                      ofItemAtPath: directory.path)
    }

    private static func isTestHost(_ environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}
