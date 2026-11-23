import Foundation
import SwiftData

/// A logged food item or whole meal. Calories/macros are always user-editable —
/// AI photo estimates and database lookups are starting points, not gospel.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var mealTypeRaw: String = MealType.snack.rawValue
    var name: String = ""
    /// e.g. "1 bowl", "200 g", "2 slices"
    var servingDescription: String = ""
    var quantity: Double = 1

    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    /// Optional calorie range from an uncertain estimate (portion size is the hard part).
    var caloriesLow: Double?
    var caloriesHigh: Double?

    var sourceRaw: String = FoodSource.manual.rawValue
    var confidenceRaw: String?
    /// Free-text notes / the AI's stated assumptions (e.g. "assumed cooked in oil").
    var notes: String?
    var barcode: String?

    /// Meal photo, stored outside the main store for performance. When a meal has
    /// several photos this is the FIRST one (the cover); the rest live in
    /// `additionalPhotoData` so the single-photo paths keep working unchanged.
    @Attribute(.externalStorage) var photoData: Data?

    /// Extra meal photos beyond the cover, when she snapped several angles/plates of
    /// the SAME meal for one combined estimate. Optional + defaulted so older rows
    /// migrate cleanly (they simply read as `nil`). Kept small (downscaled JPEGs,
    /// capped in the capture UI) since arrays can't use external storage.
    var additionalPhotoData: [Data]?

    /// Starred by the user so it's one tap to "log again" later. Defaults false
    /// (schema-safe: older rows simply read as not-favorite).
    var isFavorite: Bool = false

    var createdAt: Date = Date.now

    // MARK: Label nutrients beyond the macros (per serving, like `calories`)
    //
    // Each is optional and `nil` means NOT KNOWN: the source did not state it. It is shown
    // as unknown and never counted as zero; `0` means the source said zero. Optional with no
    // default so older rows and rows from other devices read as unknown (CloudKit rule).
    // Read and write them through `detail`.
    var saturatedFatG: Double?
    var transFatG: Double?
    var cholesterolMg: Double?
    var sodiumMg: Double?
    var fiberG: Double?
    /// Total sugars, including any added.
    var sugarsG: Double?
    var addedSugarsG: Double?
    var vitaminDMcg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var potassiumMg: Double?

    /// The label nutrients as one value. Per serving; a day's totals multiply by `quantity`
    /// in `NutrientTotals`.
    var detail: NutrientDetail {
        get {
            var d = NutrientDetail()
            d.saturatedFatG = saturatedFatG
            d.transFatG = transFatG
            d.cholesterolMg = cholesterolMg
            d.sodiumMg = sodiumMg
            d.fiberG = fiberG
            d.sugarsG = sugarsG
            d.addedSugarsG = addedSugarsG
            d.vitaminDMcg = vitaminDMcg
            d.calciumMg = calciumMg
            d.ironMg = ironMg
            d.potassiumMg = potassiumMg
            return d
        }
        set {
            saturatedFatG = newValue.saturatedFatG
            transFatG = newValue.transFatG
            cholesterolMg = newValue.cholesterolMg
            sodiumMg = newValue.sodiumMg
            fiberG = newValue.fiberG
            sugarsG = newValue.sugarsG
            addedSugarsG = newValue.addedSugarsG
            vitaminDMcg = newValue.vitaminDMcg
            calciumMg = newValue.calciumMg
            ironMg = newValue.ironMg
            potassiumMg = newValue.potassiumMg
        }
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }
    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var confidence: EstimateConfidence? {
        get { confidenceRaw.flatMap(EstimateConfidence.init(rawValue:)) }
        set { confidenceRaw = newValue?.rawValue }
    }

    /// Nutrition for the logged AMOUNT = per-serving value × servings (`quantity`).
    /// The per-serving `calories`/`proteinG`/… stay the editable base; every screen sums
    /// these `total*` accessors so logging quantity 2 is counted correctly everywhere
    /// (previously quantity was stored but never multiplied → a silent undercount).
    var totalCalories: Double { calories * quantity }
    var totalProteinG: Double { proteinG * quantity }
    var totalCarbsG: Double { carbsG * quantity }
    var totalFatG: Double { fatG * quantity }

    init(date: Date = .now,
         mealType: MealType = .snack,
         name: String,
         servingDescription: String = "",
         quantity: Double = 1,
         calories: Double = 0,
         proteinG: Double = 0,
         carbsG: Double = 0,
         fatG: Double = 0,
         caloriesLow: Double? = nil,
         caloriesHigh: Double? = nil,
         source: FoodSource = .manual,
         confidence: EstimateConfidence? = nil,
         notes: String? = nil,
         barcode: String? = nil,
         photoData: Data? = nil,
         additionalPhotoData: [Data]? = nil,
         isFavorite: Bool = false,
         detail: NutrientDetail = NutrientDetail()) {
        self.id = UUID()
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.name = name
        self.servingDescription = servingDescription
        self.quantity = quantity
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.caloriesLow = caloriesLow
        self.caloriesHigh = caloriesHigh
        self.sourceRaw = source.rawValue
        self.confidenceRaw = confidence?.rawValue
        self.notes = notes
        self.barcode = barcode
        self.photoData = photoData
        self.additionalPhotoData = additionalPhotoData
        self.isFavorite = isFavorite
        self.createdAt = .now
        self.detail = detail
    }
}

extension FoodEntry {
    /// A new entry that repeats this one on `date` in `meal` (Recents and Favorites, "log
    /// again"). It keeps everything that describes the food: name, serving, quantity,
    /// calories, macros, the label nutrients (known and not known alike), range, source,
    /// confidence, notes, barcode and the favorite flag. It gets its own identity and
    /// timestamps, and no photo: a repeat is not the same plate, and copying the stored
    /// image would grow the store for nothing.
    func relogged(on date: Date, meal: MealType) -> FoodEntry {
        FoodEntry(date: date,
                  mealType: meal,
                  name: name,
                  servingDescription: servingDescription,
                  quantity: quantity,
                  calories: calories,
                  proteinG: proteinG,
                  carbsG: carbsG,
                  fatG: fatG,
                  caloriesLow: caloriesLow,
                  caloriesHigh: caloriesHigh,
                  source: source,
                  confidence: confidence,
                  notes: notes,
                  barcode: barcode,
                  photoData: nil,
                  isFavorite: isFavorite,
                  detail: detail)
    }
}
