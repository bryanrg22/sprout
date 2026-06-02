import SwiftUI
import SwiftData

/// Lets Victoria tune her gentle reminders: morning weigh-in, meal nudges, and
/// gym days. Every change re-asks for permission (a no-op once decided) and
/// reschedules so what's pending always matches what's on screen.
struct RemindersSettingsView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Form {
            weighInSection
            mealsSection
            gymSection
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Weigh-in

    private var weighInSection: some View {
        Section {
            Toggle("Morning weigh-in", isOn: $profile.weighInReminderEnabled)
                .tint(Theme.brand)
                .onChange(of: profile.weighInReminderEnabled) { reschedule() }

            if profile.weighInReminderEnabled {
                DatePicker("Time", selection: hourBinding(\.weighInHour),
                           displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Weigh-in")
        } footer: {
            Text("A calm morning check-in. We follow your trend, not any single day on the scale.")
        }
    }

    // MARK: Meals

    private var mealsSection: some View {
        Section {
            Toggle("Meal reminders", isOn: $profile.mealRemindersEnabled)
                .tint(Theme.brand)
                .onChange(of: profile.mealRemindersEnabled) { reschedule() }

            if profile.mealRemindersEnabled {
                DatePicker("Breakfast", selection: hourBinding(\.breakfastHour),
                           displayedComponents: .hourAndMinute)
                DatePicker("Lunch", selection: hourBinding(\.lunchHour),
                           displayedComponents: .hourAndMinute)
                DatePicker("Dinner", selection: hourBinding(\.dinnerHour),
                           displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Meals")
        } footer: {
            Text("Friendly taps to log while it's fresh. Skip any you like — there's no streak to break.")
        }
    }

    // MARK: Gym

    private var gymSection: some View {
        Section {
            Toggle("Gym reminders", isOn: $profile.gymReminderEnabled)
                .tint(Theme.brand)
                .onChange(of: profile.gymReminderEnabled) { reschedule() }

            if profile.gymReminderEnabled {
                DatePicker("Time", selection: hourBinding(\.gymHour),
                           displayedComponents: .hourAndMinute)

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Days").font(.subheadline.weight(.semibold))
                    weekdayPicker
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Gym")
        } footer: {
            Text("Pick the days that fit your week. Even 20 minutes counts — movement is a win in any amount.")
        }
    }

    /// A row of tappable Sun–Sat chips for the multi-select.
    private var weekdayPicker: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = profile.gymWeekdays.contains(weekday)
                Button {
                    toggleWeekday(weekday)
                } label: {
                    Text(Self.weekdaySymbols[weekday - 1])
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            selected ? AnyShapeStyle(Theme.brandGradient)
                                     : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        )
                        .foregroundStyle(selected ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.weekdayAccessibilityNames[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Weekday helpers

    /// Short symbols indexed 0=Sun … 6=Sat to match weekday numbers 1…7.
    private static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    private static let weekdayAccessibilityNames =
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private func toggleWeekday(_ weekday: Int) {
        if let index = profile.gymWeekdays.firstIndex(of: weekday) {
            profile.gymWeekdays.remove(at: index)
        } else {
            profile.gymWeekdays.append(weekday)
            profile.gymWeekdays.sort()
        }
        reschedule()
    }

    // MARK: Hour <-> Date binding

    /// Bridges an `Int` hour stored on the profile to the `Date` a `DatePicker`
    /// wants. Reading builds today's date at that hour; writing extracts the hour
    /// back (we only persist the hour) and reschedules.
    private func hourBinding(_ keyPath: ReferenceWritableKeyPath<UserProfile, Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let hour = min(max(profile[keyPath: keyPath], 0), 23)
                return Calendar.current.date(
                    bySettingHour: hour, minute: 0, second: 0, of: Date.now
                ) ?? Date.now
            },
            set: { newDate in
                let hour = Calendar.current.component(.hour, from: newDate)
                profile[keyPath: keyPath] = hour
                reschedule()
            }
        )
    }

    // MARK: Reschedule

    /// Re-ask for permission (no prompt once decided) and rebuild the schedule.
    private func reschedule() {
        Task {
            _ = await NotificationService.requestAuthorization()
            NotificationService.rescheduleAll(for: profile)
        }
    }
}
