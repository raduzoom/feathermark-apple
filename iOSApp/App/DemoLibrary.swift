#if DEBUG
import FeatherCore
import UIKit

/// The notes the mobile boards show, for the simulator, UI tests and screenshots. Debug builds only, and only
/// ever written into an isolated library (`AppBootstrap.shouldSeed`).
enum DemoLibrary {
    /// Fills an empty library; a library that already has notes or notebooks is left alone.
    static func seed(into library: Library) async throws {
        let counts = try await library.counts()
        guard counts.all == 0, counts.trash == 0, try await library.notebooks().isEmpty else { return }

        let personal = try await library.createNotebook(name: "Personal", parentID: nil)
        let projects = try await library.createNotebook(name: "Projects", parentID: nil)
        let home = try await library.createNotebook(name: "Home", parentID: projects.id)
        let work = try await library.createNotebook(name: "Work", parentID: projects.id)
        let travel = try await library.createNotebook(name: "Travel", parentID: nil)

        let hardware = try await library.createTag(name: "hardware")
        _ = try await library.createTag(name: "ideas")
        let reading = try await library.createTag(name: "reading")
        _ = try await library.createTag(name: "to-do")

        // Dates like the boards': today, yesterday, a few days back. Pinned notes sit above the rest.
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        func ago(minutes: Int64) -> Int64 { now - minutes * 60_000 }
        let day: Int64 = 24 * 60
        let draft = try await library.createNote(title: "Old draft", body: "Notes for a talk I didn't give.", notebookID: personal.id, modified: ago(minutes: day * 20))
        try await library.trashNote(draft.id)
        _ = try await library.createNote(title: "Bread notes", body: """
            Starter fed at 8, ready by 2.

            - 500 g flour, 350 g water, 100 g starter, 10 g salt
            - Fold every 30 minutes for 2 hours
            """, notebookID: personal.id, modified: ago(minutes: day * 8))
        _ = try await library.createNote(title: "1:1 with Mara", body: """
            ## Agenda

            1. Release dates
            2. Hiring for the spring

            > Keep the scope small enough to ship.
            """, notebookID: work.id, modified: ago(minutes: day * 5))
        _ = try await library.createNote(title: "Reading list 2027", body: """
            - [ ] *The Overstory*
            - [ ] *Braiding Sweetgrass*
            - [x] *Piranesi*
            """, notebookID: personal.id, tagIDs: [reading.id], modified: ago(minutes: day))
        _ = try await library.createNote(title: "Lisbon, spring trip", body: """
            Flights land at 10:40. Tram 28 from Martim Moniz early, before the queues.

            See the [tram map](https://www.carris.pt) before going.
            """, notebookID: travel.id, modified: ago(minutes: day * 3))
        let groceries = try await library.createNote(title: "Groceries", body: """
            - [ ] Oat milk
            - [ ] Lemons
            - [x] Rye flour
            """, notebookID: personal.id, modified: ago(minutes: 180))
        try await library.setPinned(groceries.id, true)

        let shield = try await library.addAttachment(data: shieldImage(), filename: "radiation-shield.png", mime: "image/png")
        let weather = try await library.createNote(title: "Weather station build", body: """
            Goal: reliable readings **through winter**. The sensor is a Bosch `BME280`; the old DHT22 drifted.

            ![Radiation shield](feather://attachment/\(shield.id))

            ## Parts

            - Raspberry Pi Zero 2 W
            - Radiation shield
            - [x] Order the sensor
            - [ ] Print the mount

            > Mount it two metres up, away from the wall.

            ```swift
            let celsius = Double(raw) / 100
            ```
            """, notebookID: home.id, tagIDs: [hardware.id], modified: ago(minutes: 20))
        try await library.setPinned(weather.id, true)
    }

    /// A small drawn picture (sky, hill and a white post), so the demo note has a real image attachment.
    private static func shieldImage() -> Data {
        let size = CGSize(width: 640, height: 360)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor(red: 0.86, green: 0.90, blue: 0.95, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.55, green: 0.66, blue: 0.56, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: -160, y: 230, width: 960, height: 320)).fill()
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 280, y: 90, width: 80, height: 70), cornerRadius: 10).fill()
            UIColor(red: 0.35, green: 0.38, blue: 0.40, alpha: 1).setFill()
            context.fill(CGRect(x: 314, y: 160, width: 12, height: 110))
        }
    }
}
#endif
