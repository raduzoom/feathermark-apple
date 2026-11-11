import FeatherCore
import Foundation

/// What a note row's tile shows (iPhone and iPad note list): the note's first image, or its first letter on one of
/// four tints.
public enum NoteThumbnail {
    nonisolated(unsafe) private static let imageLink = /!\[[^\]]*\]\(feather:\/\/attachment\/([0-9A-Za-z]{26})\)/

    /// The attachment id of the first image link in a note's preview, if any.
    public static func imageID(inPreview preview: String) -> ULID? {
        guard let match = preview.firstMatch(of: imageLink) else { return nil }
        return ULID(string: String(match.1))
    }

    /// The title's first letter, uppercased; "·" for an untitled note.
    public static func letter(_ title: String) -> String {
        guard let c = title.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "·" }
        return String(c).uppercased()
    }

    /// Which of the four tile tints (0–3) a note gets; stable for a note.
    public static func tint(_ id: ULID) -> Int {
        Int(id.description.unicodeScalars.reduce(0) { ($0 &* 31 &+ $1.value) % 1_000_003 } % 4)
    }
}
