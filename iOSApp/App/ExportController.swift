import FeatherAppModel
import Foundation
import Observation

/// Export Notes…: writes the library as a Markdown folder into a temporary place; the Settings screen then hands
/// it to the Files picker, and `finish()` removes whatever is left of the temporary copy.
@MainActor @Observable
final class ExportController {
    private(set) var isExporting = false
    /// "Exported 148 notes to “FeatherMark Export”." once an export is written.
    private(set) var summary: String?
    /// The exported folder waiting for the Files picker.
    private(set) var pending: URL?
    private var scratch: URL?

    /// Writes the export and names its folder "FeatherMark Export <date> <time>": the Files picker can't merge
    /// into a folder that's already there, so every export needs a name of its own.
    func exportAll(model: AppModel, now: Date = Date(), timeZone: TimeZone = .current) async -> URL? {
        guard !isExporting else { return nil }
        finish()   // an earlier export the picker never took
        isExporting = true
        defer { isExporting = false }
        let folder = FileManager.default.temporaryDirectory.appending(path: "\(Self.scratchPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            model.lastError = "Something went wrong: \(error.localizedDescription)"
            return nil
        }
        scratch = folder
        guard var report = await model.export(to: folder, notebook: nil) else {
            finish()
            return nil
        }
        let dated = report.root.deletingLastPathComponent().appending(path: "FeatherMark Export \(Self.stamp(now, timeZone))",
                                                                      directoryHint: .isDirectory)
        do {
            try FileManager.default.moveItem(at: report.root, to: dated)
            report.root = dated
        } catch {
            model.lastError = "Something went wrong: \(error.localizedDescription)"
            finish()
            return nil
        }
        summary = Formatting.exportSummary(report)
        pending = report.root
        return report.root
    }

    /// Removes the temporary export (the Files picker has moved or copied it by now, or it was cancelled).
    func finish() {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
        pending = nil
    }

    func clearSummary() { summary = nil }

    static let scratchPrefix = "FeatherMark-Export-"

    /// Removes exports the Files picker never took (the app was closed or the sheet went away mid-export).
    static func removeStaleExports(in directory: URL = FileManager.default.temporaryDirectory) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasPrefix(scratchPrefix) {
            try? fm.removeItem(at: directory.appending(path: name, directoryHint: .isDirectory))
        }
    }

    /// "2027-01-15 08.00.00" (dots: Files shows colons as slashes).
    static func stamp(_ date: Date, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: date)
    }
}
