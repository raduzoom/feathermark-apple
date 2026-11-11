import FeatherCore

/// The import sheet's state (data only; the Mac app's `Import/ImportModel.swift` runs imports).
public enum ImportState: Equatable, Sendable {
    case running(ImportProgress, sourceName: String, sizeText: String)
    case finished(ImportReport)
    case failed(String)
}
