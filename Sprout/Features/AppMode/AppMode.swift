import SwiftUI

/// The two top-level surfaces of the app.
///
/// **Home** is everyday tracking: Today, Nutrients, Progress and the coach, on a tab bar.
/// **Gym** is the workout experience on its own, with no tab bar. The switch between
/// them (`ModeSwitch`) sits at the top of each mode's main screen.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case home
    case gym

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .gym:  return "Gym"
        }
    }

    /// Where the choice is remembered between launches.
    static let storageKey = "app_mode"

    /// What a stored value means. Anything unknown (a mode removed in a later version, a
    /// hand-edited default) is Home, so the app can never open onto nothing.
    static func resolve(stored: String?) -> AppMode {
        stored.flatMap(AppMode.init(rawValue:)) ?? .home
    }

    /// The mode a launch starts in. A `--demo-tab <name>` launch argument decides it
    /// (`workouts` is Gym, any Home tab is Home); otherwise the stored choice stands.
    static func initial(arguments: [String], stored: String?) -> AppMode {
        if let index = arguments.firstIndex(of: "--demo-tab"), index + 1 < arguments.count {
            return arguments[index + 1] == "workouts" ? .gym : .home
        }
        return resolve(stored: stored)
    }

    /// The mode and Home tab to show when something asks the coach a question. The coach
    /// lives in Home, so a question asked from Gym switches surface.
    static func destinationForCoach() -> (mode: AppMode, homeTab: HomeTab) { (.home, .coach) }
}

/// The tabs of Home mode. Raw values are the tab tags.
enum HomeTab: Int, CaseIterable, Sendable {
    case today = 0
    case nutrients = 1
    case progress = 2
    case coach = 4   // kept at 4: the value the coach tab has always had

    /// The tab a `--demo-tab <name>` launch opens. `workouts` is a mode now, not a tab.
    static func initial(arguments: [String]) -> HomeTab {
        guard let index = arguments.firstIndex(of: "--demo-tab"), index + 1 < arguments.count else { return .today }
        switch arguments[index + 1] {
        case "food": return .nutrients
        case "progress": return .progress
        case "coach": return .coach
        default: return .today
        }
    }
}

/// The Home | Gym switch, built like ChatGPT's Chat | Work switch (from the owner's
/// `chatgpt-ios-ui` skeleton, MIT): two equal segments in a Liquid Glass capsule, the selected
/// one marked by a soft pill that slides between them. On iOS 18 to 25, which have no Liquid
/// Glass, the capsule is the system's thin material instead.
struct ModeSwitch: View {
    @AppStorage(AppMode.storageKey) private var stored: String = AppMode.home.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    private var mode: AppMode { AppMode.resolve(stored: stored) }

    /// The selected pill: a darker well in the dark look, a light grey wash in the light one.
    private var selectedFill: Color {
        colorScheme == .dark ? Theme.background.opacity(0.8) : Color.black.opacity(0.06)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppMode.allCases) { option in
                Button {
                    guard option != mode else { return }
                    withAnimation(reduceMotion ? nil : .default) { stored = option.rawValue }
                } label: {
                    Text(option.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 72, height: 39)
                        .background {
                            if option == mode {
                                Capsule().fill(selectedFill)
                                    .matchedGeometryEffect(id: "selected", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mode.\(option.rawValue)")
                .accessibilityAddTraits(option == mode ? [.isSelected] : [])
            }
        }
        .padding(4)
        .modeSwitchGlass()
        .sensoryFeedback(.selection, trigger: stored)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section")
    }
}

private extension View {
    /// Liquid Glass where the system has it, the thin material otherwise.
    @ViewBuilder func modeSwitchGlass() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }
}
