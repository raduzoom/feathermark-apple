import FeatherAppModel
import SwiftUI

/// Opens the model once per launch; the views wait for it.
@MainActor @Observable
final class AppLoader {
    private(set) var model: AppModel?
    private(set) var failure: String?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            do {
                let model = try await AppBootstrap.makeModel()
                await AppBootstrap.launch(model)
                self.model = model
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

@main
struct FeatherMarkApp: App {
    @State private var loader = AppLoader()
    @Environment(\.scenePhase) private var scenePhase

    init() { Theme.configureNavigationBars() }

    /// Tests only: `-FeatherColorScheme light|dark` (as on the Mac), so screenshots cover both.
    static let forcedColorScheme: ColorScheme? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-FeatherColorScheme"), i + 1 < args.count else { return nil }
        return args[i + 1] == "dark" ? .dark : args[i + 1] == "light" ? .light : nil
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = loader.model {
                    RootView(model: model)
                } else if let failure = loader.failure {
                    ContentUnavailableView("FeatherMark can't open its library.", systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                } else {
                    GlassBackground()
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(Self.forcedColorScheme)
            .task { loader.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Every edit reaches the database before the app can be suspended or killed.
            if phase == .background, let model = loader.model { Task { await model.flush() } }
        }
    }
}
