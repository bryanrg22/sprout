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

/// The Home | Gym switch: a capsule with two segments, the selected one raised.
struct ModeSwitch: View {
    @AppStorage(AppMode.storageKey) private var stored: String = AppMode.home.rawValue
    @Namespace private var highlight

    private var mode: AppMode { AppMode.resolve(stored: stored) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases) { option in
                Button {
                    guard option != mode else { return }
                    withAnimation(.snappy(duration: 0.28)) { stored = option.rawValue }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(option == mode ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 20)
                        .frame(height: 36)
                        .background {
                            if option == mode {
                                Capsule().fill(Theme.cardRaised)
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
        .padding(3)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.textSecondary.opacity(0.18), lineWidth: 1))
        .sensoryFeedback(.selection, trigger: stored)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section")
    }
}
