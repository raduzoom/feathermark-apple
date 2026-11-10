import Foundation
import Observation

/// Pending alerts: a name prompt, a destructive confirmation, or an information message.
@MainActor @Observable
public final class Dialogs {
    public init() {}

    public struct NameRequest: Identifiable {
        public let id = UUID()
        public var title: String
        public var placeholder: String
        public var initial: String
        public var button: String
        public var onSubmit: (String) async -> Void
    }

    public struct ConfirmRequest: Identifiable {
        public let id = UUID()
        public var confirmation: Formatting.Confirmation
        public var onConfirm: () async -> Void
    }

    public struct Message: Identifiable {
        public let id = UUID()
        public var title: String
        public var body: String
    }

    public var name: NameRequest?
    public var confirmRequest: ConfirmRequest?
    public var message: Message?

    public func askName(title: String, placeholder: String, initial: String = "", button: String, onSubmit: @escaping (String) async -> Void) {
        name = NameRequest(title: title, placeholder: placeholder, initial: initial, button: button, onSubmit: onSubmit)
    }

    public func confirm(_ confirmation: Formatting.Confirmation, onConfirm: @escaping () async -> Void) {
        confirmRequest = ConfirmRequest(confirmation: confirmation, onConfirm: onConfirm)
    }

    public func show(title: String, body: String) {
        message = Message(title: title, body: body)
    }
}
