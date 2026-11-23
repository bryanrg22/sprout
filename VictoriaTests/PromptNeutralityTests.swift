import XCTest
import SwiftData
@testable import Victoria

/// Prompts and copy fit whoever is using the app (GOALS G7, EVAL_REPORT 3 finding A-1).
///
/// The prompts were written for one person: they said "she" and assumed a goal of losing
/// weight. These tests build every prompt the app sends for two fixture users (a man who
/// is gaining, a woman who is losing) through the real builders, and through the real
/// clients on a scripted transport, so what is scanned is the request a provider would
/// receive: system text, user turn, tool name, tool description and schema.
///
/// A prompt fails when it has a gendered pronoun, the hard-coded "weight-loss" label, or
/// either first name the app was first built around. Each prompt that is told the goal
/// direction must carry the rule for that direction and not the rule for another.
///
/// The coach's tool descriptions and schemas are scanned too, as the model receives them
/// and as source (so the replies a tool hands back to the model are covered).
///
/// Not covered here: onboarding, Settings, the buddy feature and the widgets. And one thing
/// is knowingly allowed: the two built-in characters are still stored, and offered to the
/// model, under the first names of the two people they were drawn for.
@MainActor
final class PromptNeutralityTests: XCTestCase {

    // MARK: - What a prompt must not contain

    /// Third-person pronouns about one person. Matched as whole words, so "the", "this",
    /// "there" and "where" do not match.
    private static let genderedWords: Set<String> = ["she", "her", "hers", "herself",
                                                     "he", "his", "him", "himself"]
    /// The label the prompts used whatever the goal was.
    private static let hardCodedLabel = "weight-loss"
    /// The two first names the app was built around (they are in `DemoSeed`).
    private static let builtAroundNames = ["Victoria", "Bryan"]

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Every way `text` breaks the rule, with enough context to find it.
    static func violations(in text: String) -> [String] {
        var found: [String] = []
        let tokens = words(text)
        for (index, token) in tokens.enumerated() where genderedWords.contains(token) {
            let context = tokens[max(0, index - 4)...min(tokens.count - 1, index + 4)].joined(separator: " ")
            found.append("pronoun \"\(token)\" in \"…\(context)…\"")
        }
        if text.lowercased().contains(hardCodedLabel) { found.append("\"\(hardCodedLabel)\"") }
        for name in builtAroundNames where tokens.contains(name.lowercased()) {
            found.append("the name \(name)")
        }
        return found
    }

    func testTheScannerCatchesWhatItIsFor() {
        XCTAssertFalse(Self.violations(in: "Here is her current data").isEmpty)
        XCTAssertFalse(Self.violations(in: "Never push restriction.").isEmpty)
        XCTAssertFalse(Self.violations(in: "celebrate the strength she's building").isEmpty)
        XCTAssertFalse(Self.violations(in: "that plan is hers").isEmpty)
        XCTAssertFalse(Self.violations(in: "a note she wrote herself").isEmpty)
        XCTAssertFalse(Self.violations(in: "log his water").isEmpty)
        XCTAssertFalse(Self.violations(in: "When he asks, answer him.").isEmpty)
        XCTAssertFalse(Self.violations(in: "a warm, upbeat weight-loss buddy").isEmpty)
        for name in Self.builtAroundNames {
            XCTAssertFalse(Self.violations(in: "Hi \(name)!").isEmpty)
        }
        // Whole words only.
        XCTAssertEqual(Self.violations(in: "This is the other way: there, where, sheer, usher, history, them, their."), [])
        XCTAssertEqual(Self.violations(in: "Working toward gentle, sustainable weight loss."), [],
                       "a goal the profile states is not the hard-coded label")
    }

    // MARK: - The two fixture users

    private struct User {
        let profile: UserProfile
        let foods: [FoodEntry]
        let weights: [WeightEntry]
        let water: [WaterEntry]
        let steps: [StepsEntry]
        let sessions: [WorkoutSession]
        let exercises: [ExerciseEntry]
        let sleep: [SleepEntry]
        let vitals: [VitalsEntry]
        let detected: [DetectedWorkout]
        let memory: CoachMemory
        let plan: CoachPlan
    }

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: 15, second: 0, of: base) ?? base
    }

    /// "Alex": a man, gaining. "Sam": a woman, losing. `direction` overrides the pace so a
    /// maintaining user is covered too.
    private func user(_ name: String, direction: GoalPace.Direction? = nil,
                      lastLogDaysAgo: Int = 0) -> User {
        let gaining = name == "Alex"
        let p = UserProfile()
        p.name = name
        p.sex = gaining ? .male : .female
        p.birthDate = calendar.date(byAdding: .year, value: -27, to: today) ?? today
        p.heightCm = gaining ? 178 : 165
        p.startWeightLbs = gaining ? 158 : 162
        p.goalWeightLbs = gaining ? 172 : 145
        p.activityLevel = .light
        switch direction ?? (gaining ? .gain : .lose) {
        case .gain:     p.pace = .leanGain
        case .lose:     p.pace = .relaxed
        case .maintain: p.pace = .maintain
        }
        p.dailyStepGoal = 8000
        p.onboardingComplete = true
        p.onboardingNote = "I work shifts and train after work. I like cooking on Sundays."

        let last = -lastLogDaysAgo
        let foods = [
            FoodEntry(date: day(last, hour: 8), mealType: .breakfast, name: "Greek yogurt", calories: 150,
                      proteinG: 17, carbsG: 9, fatG: 4),
            FoodEntry(date: day(last, hour: 12), mealType: .lunch, name: "Chicken burrito bowl", calories: 720,
                      proteinG: 45, carbsG: 78, fatG: 24),
            FoodEntry(date: day(last - 1, hour: 19), mealType: .dinner, name: "Salmon and rice", calories: 640,
                      proteinG: 42, carbsG: 60, fatG: 22),
        ]
        let base = gaining ? 160.0 : 158.0
        let weights = (0..<10).map { index in
            WeightEntry(date: day(last - index, hour: 7),
                        weightLbs: base + (gaining ? -0.2 : 0.2) * Double(index))
        }
        let session = WorkoutSession(date: day(last - 1, hour: 18), kind: .gym, focuses: [.legs], durationMinutes: 50)
        let memory = CoachMemory(
            profileNotes: CoachMemory.onboardingSeedLabel + p.onboardingNote + "\n"
                + PlanIntakeView.intakePrefix + "life + training: desk job · lifts three times a week",
            conversationSummary: "Talked about meal prep and a busy stretch at work.")
        let plan = CoachPlan(headline: "A steady plan for the next eight weeks",
                             assessment: "On track so far.",
                             calorieMin: 1900, calorieMax: 2150, proteinTarget: 130,
                             insights: [PlanInsight(title: "Protein at breakfast",
                                                    body: "The highest-protein mornings were the easiest days.",
                                                    tone: .win)])
        return User(
            profile: p, foods: foods, weights: weights,
            water: [WaterEntry(date: day(last, hour: 10), amountOz: 16.9)],
            steps: [StepsEntry(date: today, count: 6200)],
            sessions: [session],
            exercises: [ExerciseEntry(sessionID: session.id, date: session.date, machineKey: "leg_press",
                                      displayName: "Leg press", weightLbs: 180, reps: 10, sets: 3)],
            sleep: (0..<4).map { SleepEntry(date: calendar.date(byAdding: .day, value: -$0, to: today) ?? today,
                                            asleepMinutes: 430 - $0 * 5, deepMinutes: 70, remMinutes: 95,
                                            coreMinutes: 265 - $0 * 5, awakeMinutes: 12) },
            vitals: (0..<4).map { VitalsEntry(date: calendar.date(byAdding: .day, value: -$0, to: today) ?? today,
                                              restingHeartRate: 58 + Double($0), hrvMs: 46) },
            detected: [DetectedWorkout(healthKitUUID: "fixture-1", date: day(-2, hour: 17), activity: "Running",
                                       durationMinutes: 31, caloriesBurned: 280, sourceName: "Tracker")],
            memory: memory, plan: plan)
    }

    private var bothUsers: [User] { [user("Alex"), user("Sam")] }
    /// Both fixture users, each on every goal direction.
    private var everyUserAndDirection: [User] {
        ["Alex", "Sam"].flatMap { name in
            [GoalPace.Direction.lose, .maintain, .gain].map { user(name, direction: $0) }
        }
    }

    // MARK: - Capturing what a feature sends

    /// Every string in a decoded JSON body, one per line (keys excluded).
    private func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let list = value as? [Any] { return list.flatMap(strings(in:)) }
        if let dict = value as? [String: Any] { return dict.values.flatMap(strings(in:)) }
        return []
    }

    /// Runs `call` against a transport that records the request and answers nothing, and
    /// returns every string the client put in the request body.
    private func sent(_ call: () async -> Void) async -> String {
        let transport = ScriptedTransport([])
        let runtime = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", transport: transport)
        await AIRuntime.$current.withValue(runtime) { await call() }
        XCTAssertEqual(transport.requests.count, 1, "the feature must have made exactly one request")
        return strings(in: transport.body()).joined(separator: "\n")
    }

    private func textReply(_ text: String) -> ScriptedTransport.Reply {
        .json(200, ["content": [["type": "text", "text": text]],
                    "usage": ["input_tokens": 10, "output_tokens": 10]])
    }

    private func scripted<T>(_ replies: [ScriptedTransport.Reply],
                             _ call: () async -> T) async -> (result: T, requests: Int) {
        let transport = ScriptedTransport(replies)
        let runtime = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", transport: transport)
        let result = await AIRuntime.$current.withValue(runtime) { await call() }
        return (result, transport.requests.count)
    }

    // MARK: - Inputs for each feature, built the way the app builds them

    private func weeklyInputs(_ u: User, trend: WeeklyReflection.Inputs.TrendShape,
                              note: Bool = true) -> WeeklyReflection.Inputs {
        WeeklyReflection.Inputs(name: u.profile.name, direction: u.profile.pace.direction,
                                note: note ? u.profile.onboardingNote : "",
                                daysLogged: 6, ateEnoughDays: 4, proteinGoalDays: 3,
                                waterGoalDays: 2, stepGoalDays: 5, workoutDays: 3, trend: trend)
    }
    private let trendShapes: [WeeklyReflection.Inputs.TrendShape] =
        [.notEnoughData, .steady, .easingDown, .droppingFast, .climbing]

    private func onboardingInputs(_ u: User, note: Bool = true) -> OnboardingCoachMessage.Inputs {
        OnboardingCoachMessage.Inputs(name: u.profile.name, direction: u.profile.pace.direction,
                                      paceLabel: u.profile.pace.label, activityLabel: u.profile.activityLevel.label,
                                      note: note ? u.profile.onboardingNote : "")
    }

    private func suggestionContext(_ u: User, underProtein: Bool?) -> FoodSuggestionEngine.Context {
        let direction: FoodSuggestionEngine.Direction
        switch u.profile.pace.direction {
        case .lose: direction = .lose
        case .maintain: direction = .maintain
        case .gain: direction = .gain
        }
        var context = FoodSuggestionEngine.makeContext(
            name: u.profile.name, direction: direction, calorieTarget: 2000, proteinTarget: 130,
            caloriesEatenToday: 870, proteinEatenToday: 62, foods: u.foods,
            nearbyPlace: .init(name: "Corner Market", category: "grocery"))
        context.underProteinTrend = underProtein
        context.topFoods = [.init(name: "Chicken burrito bowl", count: 4, avgProteinG: 45)]
        return context
    }

    private func insightInputs(_ u: User) -> [DailyInsightEngine.Input] {
        func input(calories: Double, hour: Int, away: Int = 1) -> DailyInsightEngine.Input {
            DailyInsightEngine.Input(
                caloriesEaten: calories, calorieTarget: 2000, protein: 140, proteinTarget: 130,
                waterOz: 90, waterGoalOz: 80, steps: 9000, stepGoal: 8000, loggedAnythingToday: true,
                loggingStreakDays: 7, proteinHitStreakDays: 4, hydrationHitStreakDays: 3,
                workoutToday: true, hourOfDay: hour, daysAwayBeforeToday: away,
                goalDirection: u.profile.pace.direction)
        }
        var streakOfThree = input(calories: 1900, hour: 14)
        streakOfThree.loggingStreakDays = 3
        streakOfThree.workoutToday = false
        return [input(calories: 1900, hour: 14), input(calories: 600, hour: 19),
                input(calories: 600, hour: 19, away: 14), streakOfThree]
    }

    private var briefSignals: [DailyBriefService.Signals] {
        var gap = DailyBriefService.Signals(); gap.daysAway = 5
        var travelToday = DailyBriefService.Signals(); travelToday.travelShiftHours = 9; travelToday.travelShiftDaysAgo = 0
        var travelLater = DailyBriefService.Signals(); travelLater.travelShiftHours = -3; travelLater.travelShiftDaysAgo = 2
        var trend = DailyBriefService.Signals(); trend.trendEasedDown = true
        var streak = DailyBriefService.Signals(); streak.streak = 14
        var bigDay = DailyBriefService.Signals()
        bigDay.stepsYesterday = 15000; bigDay.stepsAvg = 8000; bigDay.restingHR = 59; bigDay.restingHRAvg = 59
        var sleep = DailyBriefService.Signals(); sleep.sleepMinutes = 500; sleep.sleepAvgMinutes = 420
        var deep = DailyBriefService.Signals(); deep.deepMinutes = 90
        var quiet = DailyBriefService.Signals()
        quiet.stepsYesterday = 2500; quiet.stepsAvg = 8000; quiet.restingHR = 57; quiet.restingHRAvg = 59
        return [gap, travelToday, travelLater, trend, streak, bigDay, sleep, deep, quiet, DailyBriefService.Signals()]
    }

    // MARK: - Everything the app sends or shows for one user

    private func everyPrompt(for u: User) async throws -> [(label: String, text: String)] {
        var out: [(String, String)] = []
        let profile = u.profile
        let name = profile.name

        // The coach turn: the whole system prompt, with every optional block present.
        let parts = CoachContext.systemParts(
            profile: profile, foods: u.foods, weights: u.weights, water: u.water, steps: u.steps,
            sessions: u.sessions, exercises: u.exercises, sleep: u.sleep, detected: u.detected,
            vitals: u.vitals, memory: u.memory, plan: u.plan)
        out.append(("coach system (stable)", parts.stable))
        out.append(("coach system (volatile)", parts.volatile))
        for signal in [RecoverySignal.rested, .steady, .tender] {
            out.append(("recovery line \(signal.rawValue)", signal.coachLine))
        }
        out.append(("travel line", TravelSignal.coachLine(.init(hours: 9, at: day(-1)))))
        out.append(("welcome role", CoachContext.buddyRole(profile.pace.direction)))

        // The two structured features built on the coach summary.
        let foods = u.foods, weights = u.weights, sessions = u.sessions, water = u.water, memory = u.memory
        out.append(("checklist request", await sent {
            _ = try? await ChecklistPlanService.make(profile: profile, foods: foods, weights: weights,
                                                     sessions: sessions, water: water, memory: memory)
        }))
        out.append(("coach prompt chips request", await sent {
            _ = try? await CoachPromptService.generate(profile: profile, foods: foods, weights: weights,
                                                       sessions: sessions, water: water, memory: memory)
        }))
        out.append(("fixed chips", CoachPromptService.fixedPrompts().joined(separator: "\n")))
        out.append(("checklist fallback", ChecklistPlanService.fallback().chips.map(\.title).joined(separator: "\n")))

        // Food suggestions, for each protein-trend branch.
        for underProtein in [true, false, nil] as [Bool?] {
            let context = suggestionContext(u, underProtein: underProtein)
            out.append(("food suggestions request", await sent {
                _ = try? await FoodSuggestionService.suggestions(for: context)
            }))
        }

        // The progress recap: the request around a snapshot (the snapshot builder is a
        // private view method; its source is scanned in testPromptSourceFilesAreNeutral).
        out.append(("progress recap request", await sent {
            _ = try? await ProgressSummaryService.summary(snapshot: "Goal: steady · Current logging streak: 4 day(s)")
        }))
        out.append(("meal description request", await sent {
            _ = try? await FoodPhotoAnalyzer.analyze(description: "a medium banana")
        }))

        // The insight line: every candidate the engine can pick, its template, its hint,
        // and the request the rephraser sends for it.
        for input in insightInputs(u) {
            for insight in DailyInsightEngine.allCandidates(input) {
                out.append(("insight template \(insight.id)", insight.template))
                out.append(("insight hint \(insight.id)", insight.factualHint))
                let hint = insight.factualHint.isEmpty ? insight.template : insight.factualHint
                out.append(("insight request \(insight.id)", await sent {
                    _ = await InsightPhraser.phrase(template: insight.template, factualHint: hint)
                }))
            }
        }

        // The daily brief: every rung of the ladder, as a template and as a request.
        for var signals in briefSignals {
            signals.name = name
            let picked = DailyBriefService.pick(signals)
            out.append(("brief template \(picked.topic.rawValue)", picked.headline + "\n" + picked.body))
            out.append(("brief request \(picked.topic.rawValue)", await sent {
                _ = await DailyBriefService.rephrase(picked, name: name)
            }))
        }

        // The weekly reflection: every trend shape, with and without a note.
        for shape in trendShapes {
            for note in [true, false] {
                let inputs = weeklyInputs(u, trend: shape, note: note)
                out.append(("weekly template \(shape)", WeeklyReflection.template(for: inputs)))
                out.append(("weekly request \(shape)", await sent { _ = await WeeklyReflection.make(inputs) }))
            }
        }

        // The onboarding note.
        for note in [true, false] {
            let inputs = onboardingInputs(u, note: note)
            out.append(("onboarding template", OnboardingCoachMessage.template(for: inputs)))
            out.append(("onboarding request", await sent { _ = await OnboardingCoachMessage.make(inputs) }))
        }

        // Folding chat into memory.
        let notes = u.memory.profileNotes, summary = u.memory.conversationSummary
        out.append(("memory fold request", await sent {
            _ = await CoachMemoryService.consolidate(
                currentNotes: notes, currentSummary: summary,
                olderMessages: [.init(role: "user", content: "I can't eat peanuts.", createdAt: .now),
                                .init(role: "assistant", content: "Noted, no peanuts.", createdAt: .now)],
                profileName: name)
        }))
        out.append(("memory fold request, no name", await sent {
            _ = await CoachMemoryService.consolidate(
                currentNotes: "", currentSummary: "",
                olderMessages: [.init(role: "user", content: "I can't eat peanuts.", createdAt: .now)],
                profileName: "")
        }))

        // The plan: build, research and review prompts, the teaching flags, the tool schema.
        let lowIntake = (0..<4).map { FoodEntry(date: day(-$0, hour: 12), mealType: .lunch, name: "Soup",
                                                calories: 800, proteinG: 30, carbsG: 80, fatG: 20) }
        let fastLoss = (0..<21).map { WeightEntry(date: day(-$0, hour: 7), weightLbs: 150 + Double($0)) }
        out.append(("plan system", PlanService.systemPrompt(profile: profile)))
        out.append(("plan user turn", PlanService.userContent(dataSummary: CoachContext.summary(
            profile: profile, foods: u.foods, weights: u.weights), intake: "I want to feel strong by summer.",
            about: profile.onboardingNote)))
        out.append(("plan teaching flags", PlanService.coachingNote(profile: profile, foods: lowIntake, weights: fastLoss)))
        out.append(("plan research system", PlanService.researchSystemPrompt(profile: profile)))
        out.append(("plan research turn", PlanService.researchUserContent(profile: profile, intake: "Strong by summer.")))
        out.append(("plan review system", PlanService.reviewSystemPrompt(profile: profile)))
        out.append(("plan review turn", PlanService.reviewUserContent(plan: u.plan, dataSummary: "- data", daysSince: 5,
                                                                      about: profile.onboardingNote)))
        out.append(("plan schema", strings(in: PlanService.planSchema).joined(separator: "\n")))
        return out
    }

    // MARK: - The scan

    func testNoPromptNamesAGenderALabelOrARealPerson() async throws {
        var scanned = 0
        for u in everyUserAndDirection {
            for (label, text) in try await everyPrompt(for: u) {
                scanned += 1
                XCTAssertEqual(Self.violations(in: text), [],
                               "\(label) for \(u.profile.name) (\(u.profile.pace.direction))")
            }
        }
        XCTAssertGreaterThan(scanned, 600, "the scan must have looked at every feature for every user")
    }

    /// The tools the coach is given: every name, description, property description and enum
    /// value, for both users on every goal direction and in both unit systems the profile
    /// can hold. These were written as "she" and "her" throughout until this test existed.
    func testEveryCoachToolSchemaIsNeutral() throws {
        var toolNames: Set<String> = []
        for u in everyUserAndDirection {
            let schemas = CoachTools.schemas(for: u.profile)
            XCTAssertGreaterThanOrEqual(schemas.count, 25, "the whole toolbelt, not a subset")
            for schema in schemas {
                let name = try XCTUnwrap(schema["name"] as? String)
                toolNames.insert(name)
                var text = strings(in: schema).joined(separator: "\n")
                // Allowed, and only here: the built-in characters' stored names (see the header).
                if name == CoachTools.Name.setCompanion.rawValue {
                    for avatar in CompanionAvatar.builtIns {
                        text = text.replacingOccurrences(of: avatar.rawValue, with: "", options: .caseInsensitive)
                    }
                }
                XCTAssertEqual(Self.violations(in: text), [],
                               "tool \(name) for \(u.profile.name) (\(u.profile.pace.direction))")
                XCTAssertFalse(text.contains("they is") || text.contains("they has") || text.contains("they wants")
                               || text.contains("they tells") || text.contains("they asks") || text.contains("they says"),
                               "tool \(name): a verb left in the singular after the rewording")
            }
        }
        XCTAssertGreaterThanOrEqual(toolNames.count, 25)

        // The allowance is exactly as wide as stated: without it, the companion tool is caught.
        let companion = try XCTUnwrap(CoachTools.schemas(for: user("Alex").profile)
            .first { ($0["name"] as? String) == CoachTools.Name.setCompanion.rawValue })
        XCTAssertFalse(Self.violations(in: strings(in: companion).joined(separator: "\n")).isEmpty,
                       "when the built-in characters are renamed, delete the allowance above")
    }

    /// A user back after a gap, with nothing logged today, an empty name, and a day over the
    /// calorie range: the branches the ordinary fixture does not reach.
    func testTheLessCommonCoachBranchesAreNeutralToo() {
        for name in ["Alex", "Sam"] {
            let back = user(name, lastLogDaysAgo: 9)
            XCTAssertTrue(CoachContext.summary(profile: back.profile, foods: back.foods, weights: back.weights,
                                               water: back.water).contains("days away from the app"))
            let anonymous = user(name)
            anonymous.profile.name = ""
            let big = FoodEntry(date: day(0, hour: 13), mealType: .lunch, name: "Large pizza", calories: 4200,
                                proteinG: 150, carbsG: 420, fatG: 190)
            let cases: [(String, String)] = [
                ("back after a gap", CoachContext.system(profile: back.profile, foods: back.foods,
                                                          weights: back.weights, water: back.water)),
                ("no data", CoachContext.system(profile: back.profile, foods: [], weights: [])),
                ("no name", CoachContext.system(profile: anonymous.profile, foods: anonymous.foods,
                                                weights: anonymous.weights)),
                ("over the range", CoachContext.system(profile: back.profile, foods: [big], weights: back.weights)),
            ]
            for (label, text) in cases {
                XCTAssertEqual(Self.violations(in: text), [], "\(label), \(name)")
            }
        }
    }

    // MARK: - The source of every prompt, for the builders a test cannot call

    /// Files that hold prompt text. Their code (comments removed) is scanned too, because
    /// some builders are private view methods (`ProgressSummaryCard.buildSnapshot`,
    /// `PlanIntakeView.adjustIntake`) and because a fixture cannot reach every branch.
    private static let promptSourceFiles = [
        "Victoria/Services/AI/GoalFraming.swift",
        "Victoria/Services/InsightPhraser.swift",
        "Victoria/Services/DailyInsightEngine.swift",
        "Victoria/Services/DailyBriefService.swift",
        "Victoria/Services/FoodSuggestionService.swift",
        "Victoria/Services/FoodSuggestionEngine.swift",
        "Victoria/Services/CoachPromptService.swift",
        "Victoria/Services/ChecklistPlanService.swift",
        "Victoria/Services/WeeklyReflection.swift",
        "Victoria/Services/CoachMemoryService.swift",
        "Victoria/Services/PlanService.swift",
        "Victoria/Services/ProgressSummaryService.swift",
        "Victoria/Services/FoodPhotoAnalyzer.swift",
        "Victoria/Services/RecoverySignal.swift",
        "Victoria/Services/TravelSignal.swift",
        "Victoria/Models/CoachMemory.swift",
        "Victoria/Features/Coach/CoachContext.swift",
        "Victoria/Features/Coach/CoachTools.swift",
        "Victoria/Features/Onboarding/OnboardingCoachMessage.swift",
        "Victoria/Features/Weight/ProgressSummaryCard.swift",
        "Victoria/Features/Plan/PlanIntakeView.swift",
        "Victoria/Features/Plan/PlanCard.swift",
        "Victoria/Features/Dashboard/DailyBriefCard.swift",
        "Victoria/Features/Dashboard/WeeklyReflectionCard.swift",
    ]

    /// A line of Swift without its trailing `//` comment. A `//` is a comment when an even
    /// number of quotes precede it on the line.
    static func withoutComment(_ line: String) -> String {
        var quotes = 0
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"", previous != "\\" { quotes += 1 }
            if character == "/", previous == "/", quotes.isMultiple(of: 2) {
                return String(line[..<line.index(before: index)])
            }
            previous = character
            index = line.index(after: index)
        }
        return line
    }

    func testCommentStripping() {
        XCTAssertEqual(Self.withoutComment("let a = 1 // her note"), "let a = 1 ")
        XCTAssertEqual(Self.withoutComment("    /// Her own words"), "    ")
        XCTAssertEqual(Self.withoutComment("let u = \"https://example.com\" // x"), "let u = \"https://example.com\" ")
        XCTAssertEqual(Self.withoutComment("let s = \"her // data\""), "let s = \"her // data\"")
    }

    func testPromptSourceFilesAreNeutral() throws {
        // The repository on the host, from this file's own path (the simulator reads host paths).
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for path in Self.promptSourceFiles {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            // The one place the old labels must still be spelled: the table that rewrites them.
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { Self.withoutComment(String($0)) }
                .filter { !$0.contains("(\"From her ") }
                .joined(separator: "\n")
            XCTAssertEqual(Self.violations(in: code), [], path)
        }
    }

    // MARK: - The rule for the goal direction, prompt by prompt

    private let lose = GoalFraming.protectiveRule(.lose)
    private let gain = GoalFraming.protectiveRule(.gain)
    private let maintain = GoalFraming.protectiveRule(.maintain)
    private let anyDirection = GoalFraming.protectiveRule(nil)

    private func rule(_ direction: GoalPace.Direction) -> String {
        switch direction {
        case .lose: return lose
        case .gain: return gain
        case .maintain: return maintain
        }
    }

    /// `text` carries the rule for `direction` and no other direction's rule.
    private func assertOnlyTheRule(for direction: GoalPace.Direction, in text: String, _ label: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        for candidate in [GoalPace.Direction.lose, .maintain, .gain] {
            XCTAssertEqual(text.contains(rule(candidate)), candidate == direction,
                           "\(label): rule for \(candidate) in a prompt for \(direction)", file: file, line: line)
        }
        XCTAssertFalse(text.contains(anyDirection), "\(label): a prompt that knows the direction", file: file, line: line)
    }

    func testTheRulesSayWhatTheyAreFor() {
        XCTAssertTrue(lose.contains("Never suggest eating less"))
        XCTAssertFalse(lose.contains("excessive"))
        XCTAssertTrue(gain.contains("Never describe eating as excessive"))
        XCTAssertFalse(gain.contains("eating less"))
        XCTAssertTrue(maintain.contains("eating less") && maintain.contains("excessive"))
        XCTAssertTrue(anyDirection.contains("eating less") && anyDirection.contains("excessive"))
        for text in [lose, gain, maintain, anyDirection] {
            XCTAssertTrue(text.hasSuffix(GoalFraming.noShame))
            XCTAssertEqual(Self.violations(in: text), [])
        }
        XCTAssertEqual(Set([lose, gain, maintain, anyDirection]).count, 4)
    }

    /// A model echoes its prompt. A rule that contained a phrase the output guardrails
    /// reject would get a faithful reply thrown away (EVAL_REPORT 10, defect 4).
    func testTheRulesDoNotTripTheOutputGuardrails() async {
        for text in [lose, gain, maintain, anyDirection] {
            XCTAssertNotNil(DailyBriefService.parse("A headline.\n" + text))
            XCTAssertEqual(WeeklyReflection.sanitize(text), text)
            XCTAssertEqual(OnboardingCoachMessage.sanitize(text), text)
            XCTAssertTrue(text.count > 180, "longer than an insight line, so it is checked sentence by sentence")
            for sentence in text.components(separatedBy: ". ") where !sentence.isEmpty {
                let line = String(sentence.prefix(170)).trimmingCharacters(in: .whitespaces)
                let echoed = await scripted([textReply(line)]) {
                    await InsightPhraser.rephrase(template: "t", factualHint: "h")
                }
                XCTAssertEqual(echoed.result, line, "the insight guardrail rejected a sentence of a rule")
            }
        }
    }

    func testPromptsBuiltOnTheSummaryCarryTheRuleForTheirDirection() {
        for u in everyUserAndDirection {
            let direction = u.profile.pace.direction
            let name = u.profile.name
            assertOnlyTheRule(for: direction, in: ChecklistPlanService.userPrompt(
                name: name, direction: direction, dataSummary: "- data", bio: "", memoryNotes: ""), "checklist")
            assertOnlyTheRule(for: direction, in: CoachPromptService.userPrompt(
                name: name, direction: direction, dataSummary: "- data", bio: "", memoryNotes: ""), "chips")
            assertOnlyTheRule(for: direction, in: FoodSuggestionEngine.renderPrompt(
                suggestionContext(u, underProtein: nil)), "food suggestions")
            assertOnlyTheRule(for: direction, in: OnboardingCoachMessage.userPrompt(onboardingInputs(u)), "onboarding")
            for shape in trendShapes {
                assertOnlyTheRule(for: direction, in: WeeklyReflection.userPrompt(weeklyInputs(u, trend: shape)),
                                  "weekly \(shape)")
            }
        }
    }

    /// The two rephrasers are handed a finished sentence and no direction, so their system
    /// prompt carries the rule for every direction and tells the model to use "you".
    func testRephrasersCarryTheRuleForEveryDirection() async {
        let insight = await sent { _ = await InsightPhraser.phrase(template: "t", factualHint: "h") }
        XCTAssertTrue(insight.contains(anyDirection))
        XCTAssertTrue(insight.contains("directly as \"you\""))
        for specific in [lose, gain, maintain] { XCTAssertFalse(insight.contains(specific)) }

        let picked = DailyBriefService.pick(DailyBriefService.Signals())
        let brief = await sent { _ = await DailyBriefService.rephrase(picked, name: "Alex") }
        XCTAssertTrue(brief.contains("restriction talk"), "never push eating less")
        XCTAssertTrue(brief.contains("Never describe eating as excessive"), "never frame eating as excess")
        XCTAssertTrue(brief.contains("directly as \"you\""))
        XCTAssertTrue(brief.contains("Your friend's name: Alex"))
    }

    func testCoachPersonaAndStyleFollowTheDirection() {
        for name in ["Alex", "Sam"] {
            let losing = user(name, direction: .lose).profile
            let gaining = user(name, direction: .gain).profile
            let holding = user(name, direction: .maintain).profile

            let loseStyle = CoachContext.toolGuidance(profile: losing)
            XCTAssertTrue(loseStyle.contains("\(name) is working toward gentle, sustainable weight loss."))
            XCTAssertTrue(loseStyle.contains("skipping meals to lose faster"))
            XCTAssertTrue(loseStyle.contains("a sensible deficit"))
            XCTAssertFalse(loseStyle.contains("gain faster"))

            let gainStyle = CoachContext.toolGuidance(profile: gaining)
            XCTAssertTrue(gainStyle.contains("\(name) is working toward a healthy lean gain."))
            XCTAssertTrue(gainStyle.contains("never describe it as excessive"), "never frame eating as excess")
            XCTAssertTrue(gainStyle.contains("cramming in calories to gain faster"))
            XCTAssertTrue(gainStyle.contains("a modest surplus"))
            for lossOnly in ["weight loss", "lose faster", "deficit", "crash dieting"] {
                XCTAssertFalse(gainStyle.contains(lossOnly), "a gaining user's coach is told about \(lossOnly)")
            }

            let holdStyle = CoachContext.toolGuidance(profile: holding)
            XCTAssertTrue(holdStyle.contains("\(name) is maintaining a healthy weight."))
            XCTAssertFalse(holdStyle.contains("deficit"))

            XCTAssertTrue(CoachContext.persona(profile: losing).contains("friend and buddy for losing weight steadily."))
            XCTAssertTrue(CoachContext.persona(profile: gaining).contains("friend and muscle-building buddy."))
            XCTAssertTrue(CoachContext.persona(profile: holding).contains("friend and healthy-habits buddy."))
            XCTAssertFalse(CoachContext.persona(profile: gaining).contains("losing weight"))
        }
    }

    /// The tools half of the coach prompt is the same for every direction: only the
    /// coaching-style paragraph moves, so what a model was told about tools is unchanged.
    func testOnlyTheCoachingStyleParagraphDependsOnDirection() {
        func toolsHalf(_ direction: GoalPace.Direction) -> String {
            let text = CoachContext.toolGuidance(profile: user("Alex", direction: direction).profile)
            return text.components(separatedBy: "\n\nCoaching style.").first ?? ""
        }
        XCTAssertFalse(toolsHalf(.lose).isEmpty)
        XCTAssertEqual(toolsHalf(.lose), toolsHalf(.gain))
        XCTAssertEqual(toolsHalf(.lose), toolsHalf(.maintain))
        for tool in ["set_step_goal", "set_water_goal_containers", "set_pace", "log_food", "edit_food",
                     "delete_food", "log_water", "log_weight", "log_workout", "set_weight_goal",
                     "remember_about_user", "forget_about_user", "update_plan", "edit_plan"] {
            XCTAssertTrue(toolsHalf(.lose).contains(tool), "the coach is still told about \(tool)")
        }
    }

    func testPlanPromptsFollowTheDirection() {
        let losing = user("Sam").profile, gaining = user("Alex").profile
        XCTAssertTrue(PlanService.systemPrompt(profile: losing).contains("Sam, whose goal is sustainable fat loss"))
        XCTAssertTrue(PlanService.systemPrompt(profile: gaining).contains("Alex, whose goal is a healthy lean gain"))

        // Very low intake is a teaching moment for both, with the reason that fits the goal.
        let lowIntake = (0..<4).map { FoodEntry(date: day(-$0, hour: 12), mealType: .lunch, name: "Soup",
                                                calories: 800, proteinG: 30, carbsG: 80, fatG: 20) }
        let forLoss = PlanService.coachingFlags(profile: losing, foods: lowIntake, weights: [])
        let forGain = PlanService.coachingFlags(profile: gaining, foods: lowIntake, weights: [])
        XCTAssertEqual(forLoss.count, 1)
        XCTAssertEqual(forGain.count, 1)
        XCTAssertTrue(forLoss[0].contains("protects muscle in a deficit"))
        XCTAssertFalse(forGain[0].contains("deficit"), "a gaining user is not in a deficit")
        XCTAssertTrue(forGain[0].contains("a gain is built from fuel"))
        // Losing fast is only ever said to a losing user.
        let fastLoss = (0..<21).map { WeightEntry(date: day(-$0, hour: 7), weightLbs: 150 + Double($0)) }
        XCTAssertTrue(PlanService.coachingFlags(profile: losing, foods: [], weights: fastLoss)
            .contains { $0.contains("losing fast") })
        XCTAssertFalse(PlanService.coachingFlags(profile: gaining, foods: [], weights: fastLoss)
            .contains { $0.contains("losing fast") })
    }

    // MARK: - Templates read the trend for the user's goal

    func testWellFueledLineNamesTheRightGoal() throws {
        func line(_ direction: GoalPace.Direction?) throws -> String {
            var input = insightInputs(user("Alex"))[0]
            input.goalDirection = direction
            return try XCTUnwrap(DailyInsightEngine.allCandidates(input).first { $0.id == "well_fueled" }).template
        }
        XCTAssertTrue(try line(.lose).contains("how the weight comes off and stays off"))
        XCTAssertTrue(try line(.gain).contains("how the strength gets built"))
        XCTAssertTrue(try line(.maintain).contains("how you stay steady"))
        for direction in [GoalPace.Direction.gain, .maintain, nil] {
            XCTAssertFalse(try line(direction).contains("comes off"), "only a losing user is told weight comes off")
        }
    }

    /// A falling trend is progress only for someone losing; a climbing one only for someone
    /// gaining; a steady one is the goal for someone maintaining.
    func testWeeklyReflectionReadsTheTrendForTheGoal() {
        let losing = user("Sam"), gaining = user("Alex"), holding = user("Sam", direction: .maintain)

        XCTAssertTrue(WeeklyReflection.trendLine(weeklyInputs(losing, trend: .easingDown)).contains("CELEBRATE"))
        XCTAssertFalse(WeeklyReflection.trendLine(weeklyInputs(gaining, trend: .easingDown)).contains("CELEBRATE"))
        XCTAssertFalse(WeeklyReflection.trendLine(weeklyInputs(holding, trend: .easingDown)).contains("CELEBRATE"))
        XCTAssertTrue(WeeklyReflection.trendLine(weeklyInputs(gaining, trend: .climbing)).contains("right on track"))
        XCTAssertFalse(WeeklyReflection.trendLine(weeklyInputs(losing, trend: .climbing)).contains("right on track"))
        XCTAssertTrue(WeeklyReflection.trendLine(weeklyInputs(losing, trend: .droppingFast)).contains("Celebrate the drive"))
        XCTAssertFalse(WeeklyReflection.trendLine(weeklyInputs(gaining, trend: .droppingFast)).contains("Celebrate"))
        XCTAssertTrue(WeeklyReflection.trendLine(weeklyInputs(holding, trend: .steady)).contains("exactly the goal"))

        XCTAssertTrue(WeeklyReflection.template(for: weeklyInputs(losing, trend: .easingDown)).contains("that's real progress"))
        XCTAssertFalse(WeeklyReflection.template(for: weeklyInputs(gaining, trend: .easingDown)).contains("progress"))
        XCTAssertFalse(WeeklyReflection.template(for: weeklyInputs(gaining, trend: .droppingFast)).contains("I love the drive"))
        XCTAssertTrue(WeeklyReflection.template(for: weeklyInputs(gaining, trend: .climbing)).contains("right on track"))
        XCTAssertTrue(WeeklyReflection.template(for: weeklyInputs(holding, trend: .steady)).contains("exactly the goal"))
    }

    /// The losing user's weekly template is what it was before the goal direction was read:
    /// the sentences are pinned word for word.
    func testWeeklyTemplateForALosingUserIsUnchanged() {
        let losing = user("Sam")
        let expected: [(WeeklyReflection.Inputs.TrendShape, String)] = [
            (.droppingFast, "Your trend dropped fast this week — I love the drive! One friendly heads-up: losing this quickly usually means you're not eating quite enough, which can cost you energy and muscle and tends to bounce back. Eat enough to fuel yourself and keep your protein up — you'll still hit your goal, and it'll actually stick."),
            (.easingDown, "And your trend is easing down — that's real progress, and the sustainable kind that lasts. It's working, so keep doing exactly what you're doing."),
            (.steady, "The scale held steady this week, which is totally normal — plateaus happen, and they usually break when you stay consistent. Keep going; it's coming."),
            (.climbing, "The scale ticked up a touch this week, but that's just normal day-to-day noise — water, food, hormones. The long trend is what counts, so don't sweat it."),
            (.notEnoughData, "We don't have quite enough weigh-ins to read your trend yet — hop on the scale a couple times next week and I'll show you how it's moving."),
        ]
        for (shape, middle) in expected {
            let note = WeeklyReflection.template(for: weeklyInputs(losing, trend: shape))
            XCTAssertEqual(note, "Sam, you showed up almost every day this week — checking in six times. That consistency is the whole game, and I'm proud of you. 💛 "
                + middle
                + " I'm keeping what you shared with me close, and we'll keep shaping this around your real life — gently, one small step at a time, together.")
        }
    }

    // MARK: - The cached prefix still does not move with data

    func testStablePrefixIsDataIndependentForBothUsers() {
        for u in bothUsers {
            let empty = CoachContext.systemParts(profile: u.profile, foods: [], weights: [])
            let full = CoachContext.systemParts(
                profile: u.profile, foods: u.foods, weights: u.weights, water: u.water, steps: u.steps,
                sessions: u.sessions, exercises: u.exercises, sleep: u.sleep, detected: u.detected,
                vitals: u.vitals, memory: u.memory, plan: u.plan)
            XCTAssertEqual(empty.stable, full.stable, "data moved into the cached prefix for \(u.profile.name)")
            for dataOnly in ["Greek yogurt", "Leg press", "Protein at breakfast", "meal prep", "kcal"] {
                XCTAssertFalse(full.stable.contains(dataOnly), "\(dataOnly) is data and belongs after the breakpoint")
            }
            XCTAssertTrue(full.volatile.contains("Greek yogurt"))
            XCTAssertFalse(full.stable.contains("Today's date"), "no date in the cached prefix")
            XCTAssertTrue(full.volatile.contains("Today's date is"))
        }
        // The prefix does differ between users: the name and the goal direction are profile facts.
        XCTAssertNotEqual(CoachContext.systemParts(profile: bothUsers[0].profile, foods: [], weights: []).stable,
                          CoachContext.systemParts(profile: bothUsers[1].profile, foods: [], weights: []).stable)
    }

    // MARK: - The labels the app writes into the coach's notes

    private func makeContext() throws -> ModelContext {
        let schema = Schema([CoachMemory.self, UserProfile.self])
        let container = try ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testOnboardingSeedLabelIsNeutral() throws {
        let context = try makeContext()
        let memory = CoachMemory.fetchOrCreate(in: context, profile: user("Alex").profile)
        XCTAssertEqual(memory.profileNotes,
                       "From the user's onboarding note (the user's own words): I work shifts and train after work. I like cooking on Sundays.")
        XCTAssertEqual(Self.violations(in: memory.profileNotes), [])
        XCTAssertEqual(Self.violations(in: PlanIntakeView.intakePrefix), [])
    }

    /// Notes written by an earlier build said "her" about every user. They are relabelled the
    /// next time the memory is fetched; the words the user wrote are not touched.
    func testNotesSeededByAnEarlierBuildAreRelabelled() throws {
        let context = try makeContext()
        let old = "From her onboarding note (her own words): I told her about my knee.\n"
            + "- likes oat milk\n"
            + "From her plan intake — her life + training: desk job · lifts 3x/week"
        context.insert(CoachMemory(profileNotes: old))
        try context.save()

        let memory = CoachMemory.fetchOrCreate(in: context, profile: nil)
        XCTAssertEqual(memory.profileNotes,
                       "From the user's onboarding note (the user's own words): I told her about my knee.\n"
                       + "- likes oat milk\n"
                       + "From the user's plan intake — life + training: desk job · lifts 3x/week")
        // A rebuilt plan still replaces the relabelled intake line instead of stacking a second.
        let rebuilt = PlanIntakeView.foldingIntake(PlanIntakeView.intakePrefix + "life + training: new job",
                                                   into: memory.profileNotes, prefix: PlanIntakeView.intakePrefix)
        XCTAssertEqual(rebuilt.components(separatedBy: PlanIntakeView.intakePrefix).count - 1, 1)
        // Notes with no old label are returned as they are.
        XCTAssertEqual(CoachMemory.neutralizingLegacyLabels("- likes oat milk"), "- likes oat milk")
        XCTAssertEqual(CoachMemory.neutralizingLegacyLabels(memory.profileNotes), memory.profileNotes)
    }

    // MARK: - The three notes still fall back to their template

    func testInsightLineIsUsedOrFallsBack() async {
        let template = "4 days of hitting your protein in a row — your body is getting exactly what it needs. 🌟"
        let good = await scripted([textReply("\"Four days of protein in a row, you're on a roll!\"")]) {
            await InsightPhraser.phrase(template: template, factualHint: "h")
        }
        XCTAssertEqual(good.result, "Four days of protein in a row, you're on a roll!", "wrapping quotes are removed")
        let banned = await scripted([textReply("Nice streak, no need to cut back now!")]) {
            await InsightPhraser.phrase(template: template, factualHint: "h")
        }
        XCTAssertEqual(banned.result, template, "a banned phrase falls back to the template")
        let tooLong = await scripted([textReply(String(repeating: "great ", count: 40))]) {
            await InsightPhraser.rephrase(template: template, factualHint: "h")
        }
        XCTAssertNil(tooLong.result)
        let failed = await scripted([.json(500, ["error": ["message": "boom"]])]) {
            await InsightPhraser.phrase(template: template, factualHint: "h")
        }
        XCTAssertEqual(failed.result, template)
        let noKey = ScriptedTransport([])
        let unkeyed = await AIRuntime.$current.withValue(AIRuntime(provider: .anthropic, apiKey: "", transport: noKey)) {
            await InsightPhraser.phrase(template: template, factualHint: "h")
        }
        XCTAssertEqual(unkeyed, template)
        XCTAssertEqual(noKey.requests.count, 0, "no key, no request")
    }

    func testWeeklyReflectionIsUsedOrFallsBack() async {
        let inputs = weeklyInputs(user("Alex"), trend: .climbing)
        let template = WeeklyReflection.template(for: inputs)
        let good = await scripted([textReply("Alex, six days of showing up. That is the whole game.")]) {
            await WeeklyReflection.make(inputs)
        }
        XCTAssertEqual(good.result, "Alex, six days of showing up. That is the whole game.")
        let digit = await scripted([textReply("Alex, try for 2500 calories next week.")]) {
            await WeeklyReflection.make(inputs)
        }
        XCTAssertEqual(digit.result, template, "a digit falls back to the template")
        let rejected = await scripted([textReply("Alex, try for 2500 calories next week.")]) {
            await WeeklyReflection.written(inputs)
        }
        XCTAssertNil(rejected.result, "the variant an evaluation calls says the reply was not used")
        let failed = await scripted([.json(500, ["error": ["message": "boom"]])]) { await WeeklyReflection.make(inputs) }
        XCTAssertEqual(failed.result, template)
    }

    func testOnboardingNoteIsUsedOrFallsBack() async {
        let inputs = onboardingInputs(user("Sam"))
        let template = OnboardingCoachMessage.template(for: inputs)
        let good = await scripted([textReply("Sam, you're in. Let's get to work.")]) {
            await OnboardingCoachMessage.make(inputs)
        }
        XCTAssertEqual(good.result, "Sam, you're in. Let's get to work.")
        let digit = await scripted([textReply("Sam, aim for 1600 calories.")]) { await OnboardingCoachMessage.make(inputs) }
        XCTAssertEqual(digit.result, template)
        let rejected = await scripted([textReply("Sam, aim for 1600 calories.")]) {
            await OnboardingCoachMessage.written(inputs)
        }
        XCTAssertNil(rejected.result)
        let failed = await scripted([.json(500, ["error": ["message": "boom"]])]) {
            await OnboardingCoachMessage.make(inputs)
        }
        XCTAssertEqual(failed.result, template)
    }
}
