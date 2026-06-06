import SwiftUI
import SwiftData
import UIKit

/// Exports everything the user has logged to one JSON file they can save, AirDrop, or
/// email to themselves — a real backup so reinstalling (or anything) can never feel like
/// losing it all. Photo blobs are excluded to keep the file small + shareable; all the
/// nutrition / weight / water / steps / workout / chat data is here.
enum DataExport {

    struct Backup: Codable {
        var exportedAt: Date
        var appVersion: String
        var profile: ProfileDTO?
        var food: [FoodDTO]
        var weights: [WeightDTO]
        var water: [WaterDTO]
        var steps: [StepsDTO]
        var workouts: [WorkoutDTO]
        var chat: [ChatDTO]
    }

    struct ProfileDTO: Codable {
        var name: String
        var startWeightLbs: Double
        var goalWeightLbs: Double
        var dailyStepGoal: Int
        var waterTargetOz: Double
    }
    struct FoodDTO: Codable {
        var date: Date; var meal: String; var name: String; var serving: String
        var quantity: Double; var calories: Double; var protein: Double
        var carbs: Double; var fat: Double; var source: String; var notes: String?
    }
    struct WeightDTO: Codable { var date: Date; var weightLbs: Double; var note: String? }
    struct WaterDTO: Codable { var date: Date; var amountOz: Double }
    struct StepsDTO: Codable { var date: Date; var count: Int }
    struct WorkoutDTO: Codable { var date: Date; var type: String; var title: String; var minutes: Int; var notes: String? }
    struct ChatDTO: Codable { var role: String; var content: String; var date: Date }

    /// Builds the backup file and returns its URL (in the temp dir), or nil on failure.
    @MainActor
    static func makeBackup(context: ModelContext, profile: UserProfile?) -> URL? {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        let backup = Backup(
            exportedAt: .now,
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")",
            profile: profile.map {
                ProfileDTO(name: $0.name, startWeightLbs: $0.startWeightLbs,
                           goalWeightLbs: $0.goalWeightLbs, dailyStepGoal: $0.dailyStepGoal,
                           waterTargetOz: $0.waterTargetOz)
            },
            food: fetch(FoodEntry.self).map {
                FoodDTO(date: $0.date, meal: $0.mealTypeRaw, name: $0.name,
                        serving: $0.servingDescription, quantity: $0.quantity, calories: $0.calories,
                        protein: $0.proteinG, carbs: $0.carbsG, fat: $0.fatG,
                        source: $0.sourceRaw, notes: $0.notes)
            },
            weights: fetch(WeightEntry.self).map { WeightDTO(date: $0.date, weightLbs: $0.weightLbs, note: $0.note) },
            water: fetch(WaterEntry.self).map { WaterDTO(date: $0.date, amountOz: $0.amountOz) },
            steps: fetch(StepsEntry.self).map { StepsDTO(date: $0.date, count: $0.count) },
            // Export the real Workouts-tab sessions — the legacy `WorkoutEntry` table is debug-only,
            // so a real user's backup was silently empty of workouts. Focuses stand in for "title".
            workouts: fetch(WorkoutSession.self).map {
                WorkoutDTO(date: $0.date, type: $0.typeRaw, title: $0.focusesRaw,
                           minutes: $0.durationMinutes, notes: $0.notes)
            },
            chat: fetch(ChatMessage.self)
                .filter { !$0.isSystemSeed }
                .map { ChatDTO(role: $0.roleRaw, content: $0.content, date: $0.createdAt) }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup) else {
            Diagnostics.shared.log("export: encode failed", .error)
            return nil
        }

        let stamp = ISO8601DateFormatter().string(from: .now).prefix(10)   // yyyy-MM-dd
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sprout-backup-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            Diagnostics.shared.log("export: \(backup.food.count) food, \(backup.weights.count) weights, \(Int(data.count/1024))KB", .app)
            return url
        } catch {
            Diagnostics.shared.log("export: write failed \(error)", .error)
            return nil
        }
    }
}

/// Small UIKit share-sheet wrapper so the backup file can be saved / AirDropped / emailed.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
