/// The accessibility identifiers the UI smoke flows (`VictoriaUITests`) find controls by.
///
/// This file is compiled into the app AND into the UI test bundle (see `project.yml`),
/// so a flow and the view it drives cannot disagree about a string. An identifier is
/// not read out by VoiceOver and is not copy: rewording a label does not break a flow.
enum AccessibilityID {
    /// The Home | Gym switch (`ModeSwitch` builds these as `mode.<AppMode.rawValue>`).
    enum Mode {
        static let home = "mode.home"
        static let gym = "mode.gym"
    }

    /// The Home tab bar's items.
    enum Tab {
        static let today = "tab.today"
        static let nutrients = "tab.nutrients"
        static let progress = "tab.progress"
        static let coach = "tab.coach"
    }

    enum Onboarding {
        /// The step indicator; its label carries the step number.
        static let steps = "onboarding.steps"
        /// The footer's forward button on every step but the last (its title varies by step).
        static let next = "onboarding.next"
        /// The footer's back button; absent on the first step.
        static let back = "onboarding.back"
        /// "Start my journey", on the last step only.
        static let start = "onboarding.start"
    }

    enum Today {
        static let root = "today.root"
        static let settings = "today.settings"
        /// The hero's eaten-calories row; its label carries the number.
        static let caloriesEaten = "today.calories.eaten"
        /// "<containers done> / <container goal>".
        static let waterCount = "today.water.count"
        /// "<amount> of <goal> <unit>".
        static let waterAmount = "today.water.amount"
        static let waterAdd = "today.water.add"
    }

    enum Nutrients {
        static let root = "nutrients.root"
        static let add = "nutrients.add"
        static let addManual = "nutrients.add.manual"
        static let dayLabel = "nutrients.day.label"
        /// One logged food; its label carries the name and the calories.
        static let foodRow = "nutrients.food.row"
        static let foodRowDelete = "nutrients.food.row.delete"
    }

    enum AddFood {
        static let name = "addFood.name"
        static let calories = "addFood.calories"
        static let save = "addFood.save"
    }

    enum Progress {
        static let root = "progress.root"
    }

    enum Coach {
        static let input = "coach.input"
        static let send = "coach.send"
        static let userMessage = "coach.message.user"
        static let assistantMessage = "coach.message.assistant"
        static let typing = "coach.typing"
        static let errorBanner = "coach.error"
        static let undo = "coach.undo"
    }

    enum Workouts {
        static let root = "workouts.root"
        static let log = "workouts.log"
        /// One logged session; its label carries the title and the summary.
        static let sessionRow = "workouts.session.row"
    }

    enum WorkoutLog {
        /// A kind tile is `workoutLog.kind.<WorkoutKind.rawValue>`.
        static func kind(_ rawValue: String) -> String { "workoutLog.kind.\(rawValue)" }
        static let minutes = "workoutLog.minutes"
        static let save = "workoutLog.save"
    }

    enum Settings {
        static let done = "settings.done"
    }
}
