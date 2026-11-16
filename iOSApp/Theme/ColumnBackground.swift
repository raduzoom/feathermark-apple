import SwiftUI

extension EnvironmentValues {
    /// iPad: the columns sit side by side (the window has a regular width). Set once by `RootView`; the columns
    /// themselves report a compact size class, so views ask this instead.
    @Entry var splitLayout = false
    /// The window's top safe area (the status bar), where the glass panels start.
    @Entry var panelTop: CGFloat = 0
    /// The window's size, so each column can draw its part of the one window background.
    @Entry var windowSize: CGSize = .zero
}

/// Which column a glass panel belongs to (Mint Glass: white library, peach list, mint editor).
enum PanelKind {
    case library, list, editor

    var fill: Color {
        switch self {
        case .library: Theme.panelLibrary
        case .list: Theme.panelList
        case .editor: Theme.panelEditor
        }
    }
}

/// A column's background. On iPhone (and in Slide Over) the whole screen is the glass background. With the columns
/// side by side, the list and the editor are floating rounded glass panels, 12 pt from their neighbours and the window
/// edges (board tablet-main-ipados-landscape-light). The library is the system's own floating glass sidebar there, so
/// it draws nothing of its own.
private struct ColumnBackground: ViewModifier {
    let kind: PanelKind
    @Environment(\.splitLayout) private var split
    @Environment(\.panelTop) private var top

    func body(content: Content) -> some View {
        if !split {
            content.background(GlassBackground())
        } else if kind == .library {
            content
        } else {
            content
                .background {
                    panel(kind.fill).overlay { panelShape.strokeBorder(Theme.panelEdge, lineWidth: 1).padded(top) }
                }
                .background { WindowBackdrop() }
        }
    }

    private var panelShape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous) }

    private func panel(_ fill: Color) -> some View {
        panelShape.fill(fill).padded(top).accessibilityHidden(true)
    }
}

/// This column's part of the window background, placed in window coordinates so the columns join without a seam. It
/// covers the column's own opaque background, which `containerBackground` doesn't clear in a split view.
private struct WindowBackdrop: View {
    @Environment(\.windowSize) private var window

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            GlassBackground()
                .frame(width: window.width, height: window.height)
                .offset(x: -frame.minX, y: -frame.minY)
        }
        .clipped()   // before ignoring the safe area: clipping after it would cut the backdrop back to the safe area
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Insets a panel inside its column: half the gap at each side (the root adds the other half at the window edges),
    /// below the status bar, and a gap above the bottom edge.
    func padded(_ top: CGFloat) -> some View {
        padding(.horizontal, Theme.panelGap / 2)
            .padding(.top, top + Theme.s8)
            .padding(.bottom, Theme.panelGap)
            .ignoresSafeArea()
    }
}

extension View {
    func columnBackground(_ kind: PanelKind) -> some View { modifier(ColumnBackground(kind: kind)) }
}
