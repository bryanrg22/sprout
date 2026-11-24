import SwiftUI

/// "App Icon" — lets the user re-skin the home-screen icon. The default is the
/// **Sprout** seedling (matches the app name); three alternates ship too: the
/// shared **Panda**, **Cute** (warm), and **Bryan** (cool/dark).
///
/// Design: a native insetGrouped `Form` over `Theme.background`, same tinted-icon
/// rhythm as the other Settings screens. Each option is a tappable row with a
/// pixel-art thumbnail (reusing the in-app `PixelPandaView` / `PixelCuteView`
/// / `PixelBryanView` renderers so previews match the real characters, plus a
/// small seedling drawn here for Sprout), a name, and a checkmark on the active one.
///
/// Mechanics: tapping calls `UIApplication.shared.setAlternateIconName(_:)` with
/// `nil` for the default Sprout and the asset-catalog name (`"AppIconPanda"` etc.)
/// for an alternate. We optimistically reflect the tapped choice, then revert if
/// the system reports an error (e.g. the icon set is missing). The selection is
/// read back from `alternateIconName`, the system's source of truth.
struct AppIconPickerView: View {

    /// One selectable icon. `iconName` is the alternate-icon asset name, or `nil`
    /// for the bundled default (Sprout).
    private struct Option: Identifiable {
        let id: String
        let name: String
        let iconName: String?       // nil = default (primary) icon
        let blurb: String
    }

    private let options: [Option] = [
        .init(id: "sprout",   name: "Sprout",   iconName: nil,              blurb: "The default seedling"),
        .init(id: "panda",    name: "Panda",    iconName: "AppIconPanda",   blurb: "Your shared buddy"),
        // `AppIconVictoria` is the asset's shipped name: iOS stores the chosen icon by it.
        .init(id: "cute", name: "Cute", iconName: "AppIconVictoria", blurb: "Warm & soft"),
        .init(id: "bryan",    name: "Bryan",    iconName: "AppIconBryan",   blurb: "Bold & electric"),
    ]

    /// The currently-applied icon, read from the system. `nil` = default Sprout.
    @State private var selected: String? = UIApplication.shared.alternateIconName

    /// Set when the system rejects a change, surfaced as a gentle inline note + alert.
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Form {
            Section {
                ForEach(options) { option in
                    Button {
                        apply(option)
                    } label: {
                        row(for: option)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionHeader("Choose your icon")
            } footer: {
                footer("Pick the icon you see on your home screen. The default Sprout matches the app’s name — the others are your companions. iOS briefly shows a confirmation when it changes.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.brand)
        // Keep the UI in sync if the icon was changed elsewhere while away.
        .onAppear { selected = UIApplication.shared.alternateIconName }
        .alert("Couldn’t change the icon", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Row

    private func row(for option: Option) -> some View {
        let isSelected = option.iconName == selected
        return HStack(spacing: Theme.Space.md) {
            thumbnail(for: option)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(isSelected ? Theme.brand : Theme.divider,
                                      lineWidth: isSelected ? 2 : 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(option.blurb)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.brand : Theme.textSecondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.name) icon. \(option.blurb).")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Pixel-art preview on a matching backdrop, echoing each rendered icon's look.
    @ViewBuilder
    private func thumbnail(for option: Option) -> some View {
        switch option.id {
        case "panda":
            iconBackdrop(Color(hex: 0xCFE6CB)) {        // soft sage/mint
                PixelArtView(rows: PixelPanda.rows(mood: .okay), palette: PixelPanda.palette)
                    .padding(6)
            }
        case "victoria":
            iconBackdrop(Color(hex: 0xF2976F)) {        // warm coral
                PixelArtView(rows: PixelCute.rows(mood: .happy, eyesOpen: true),
                             palette: PixelCute.palette)
                    .padding(6)
            }
        case "bryan":
            iconBackdrop(Color(hex: 0x0A0C0B)) {        // near-black
                PixelArtView(rows: PixelBryan.rows(mood: .happy, eyesOpen: true),
                             palette: PixelBryan.palette)
                    .padding(6)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(hex: 0xC6FF3D), lineWidth: 2)
                            .padding(6)
                    )
            }
        default:    // sprout (default)
            iconBackdrop(nil, gradient: LinearGradient(
                colors: [Color(hex: 0xF8F1E7), Color(hex: 0xF2976F)],
                startPoint: .bottom, endPoint: .top)) {
                PixelArtView(rows: PixelSprout.rows, palette: PixelSprout.palette)
                    .padding(6)
            }
        }
    }

    /// A square icon-style backdrop (solid color OR a gradient) with the pixel art on top.
    @ViewBuilder
    private func iconBackdrop<Content: View>(_ color: Color?,
                                             gradient: LinearGradient? = nil,
                                             @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            if let gradient { gradient } else if let color { color }
            content()
        }
    }

    // MARK: - Apply

    /// Optimistically reflect the tapped icon, ask the system to switch, and revert
    /// on failure. Guards `supportsAlternateIcons` and runs on the main thread.
    private func apply(_ option: Option) {
        guard option.iconName != selected else { return }   // already active
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "This device doesn’t support changing the app icon."
            showError = true
            return
        }

        let previous = selected
        selected = option.iconName                          // optimistic

        UIApplication.shared.setAlternateIconName(option.iconName) { error in
            // The completion handler's thread isn't guaranteed across iOS versions,
            // so hop to the main actor before touching SwiftUI @State.
            Task { @MainActor in
                if let error {
                    selected = previous                      // revert
                    errorMessage = error.localizedDescription
                    showError = true
                } else {
                    // Trust the system as the source of truth.
                    selected = UIApplication.shared.alternateIconName
                }
            }
        }
    }

    // MARK: - Style helpers (mirror the other Settings subviews)

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Pixel Sprout (icon-only seedling)

/// A small icon-style seedling — terracotta pot + soil, green stem, leaves. Drawn
/// here (the app's other characters live in `PixelCompanion.swift`) purely so the
/// default-icon thumbnail matches the rendered `AppIcon` art. Uses the shared
/// `PixelArtView` renderer.
enum PixelSprout {
    static let palette: [Character: Color] = [
        ".": .clear,
        "L": Color(hex: 0x7CC36B),   // leaf
        "l": Color(hex: 0x5FA84F),   // leaf shadow
        "V": Color(hex: 0x4F8F3F),   // stem
        "S": Color(hex: 0x6B4A2F),   // soil
        "P": Color(hex: 0xCB6A43),   // pot (terracotta)
        "p": Color(hex: 0xB1532F),   // pot shadow
        "R": Color(hex: 0xDD7E55),   // pot rim
        "W": Color(hex: 0xFFFFFF),   // dew highlight
    ]

    static let rows: [String] = [
        ".......V........",
        "...LL..V..LL....",
        "..LLLL.V.LLLL...",
        "..LLLWLVLWLLL...",
        "..lLLLLVLLLLl...",
        "...llL.V.Lll....",
        ".......V........",
        ".......V........",
        "...RRRRRRRRRR...",
        "...SSSSSSSSSS...",
        "...PSSSSSSSSP...",
        "....PPPPPPPP....",
        "....PpPPPPpP....",
        ".....pPPPPp.....",
    ]
}

#if DEBUG
#Preview("App Icon picker") {
    NavigationStack { AppIconPickerView() }
        .preferredColorScheme(.dark)
}
#endif
