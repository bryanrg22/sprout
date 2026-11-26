import Foundation
import UIKit
import XCTest
@testable import Sprout

/// mealPhoto: a photo of a plate → calories and macros, against Nutrition5k's weighed truth
/// (`Evals/datasets/meal_photo/v1.jsonl`, 30 cafeteria plates; see its ATTRIBUTION.md).
///
/// The photo goes through what `PhotoFoodFlow` does before it is sent (scaled to
/// `UIImage.mealPhotoMaxEdge`, then `mealPhotoUpload()`), then the app's own
/// `FoodPhotoAnalyzer.analyze(imageData:userNote:)` with no note. Graded by `Graders.meal`, the
/// same rule as a typed description: calories within 20%. Published error for comparison
/// (Thames et al. 2021, Table 3, on the same test split): 18.8% from overhead RGB-D, 26.1%
/// from 2D video frames; people 41-53% (their Figure 7).
extension LiveEvals {

    struct PhotoCase: Decodable, Sendable {
        struct Ingredient: Decodable, Sendable { let name: String; let grams: Double; let kcal: Double }
        let id: String
        let kcal: Double
        let mass_g: Double
        let fat_g: Double
        let carbs_g: Double
        let protein_g: Double
        let ingredients: [Ingredient]
        /// Relative to the dataset folder, e.g. `photos/dish_1557937157.jpg`.
        let photo: String

        /// The truth the meal grader reads. The description is the weighed ingredient list,
        /// for a person reading a failure; the model never sees it.
        var truth: Graders.MealTruth {
            Graders.MealTruth(id: id,
                              description: ingredients.map { "\(Int($0.grams.rounded())) g \($0.name)" }
                                  .joined(separator: ", "),
                              kcal: kcal, protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g,
                              source: "Nutrition5k \(id)")
        }
    }

    func testMealPhoto() async throws {
        try EvalEnv.requireLive()
        guard let root = EvalEnv.root else { throw XCTSkip("SPROUT_EVAL_ROOT not set") }
        let folder = root.appendingPathComponent("datasets/meal_photo")
        let cases = try EvalDataset.load("meal_photo/v1.jsonl", as: PhotoCase.self)
        try await EvalRunner.run(task: .mealPhoto, dataset: "meal_photo/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.photoAttempt(item, folder: folder)
        }
    }

    static func photoAttempt(_ item: PhotoCase, folder: URL) async -> EvalOutcome {
        guard let bytes = try? Data(contentsOf: folder.appendingPathComponent(item.photo)),
              let image = UIImage(data: bytes),
              let upload = image.downscaled(maxEdge: UIImage.mealPhotoMaxEdge).mealPhotoUpload() else {
            return EvalOutcome(ok: false, error: "photo \(item.photo) did not load", scores: [:], pass: false, output: "")
        }
        do {
            let estimate = try await FoodPhotoAnalyzer.analyze(imageData: upload, userNote: nil)
            let graded = Graders.meal(estimate, truth: item.truth)
            let output = (try? JSONEncoder().encode(estimate)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            return EvalOutcome(ok: true, error: nil, scores: graded.scores, pass: graded.pass, output: output)
        } catch {
            return .failed(error)
        }
    }
}
