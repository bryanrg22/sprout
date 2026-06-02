import SwiftUI

/// Text-search logging: query Open Food Facts, pick a result, then confirm in
/// `AddFoodSheet`.
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss

    /// The day to log the resulting entry to.
    let date: Date

    @State private var query: String = ""
    @State private var results: [OFFProduct] = []
    @State private var phase: Phase = .initial
    @State private var draft: FoodDraft?
    @State private var searchTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case initial       // nothing searched yet
        case searching
        case results
        case empty         // searched, no matches
        case failed
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background)
                .navigationTitle("Search Foods")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search foods, e.g. greek yogurt")
                .onSubmit(of: .search) { runSearch() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .sheet(item: $draft, onDismiss: { dismiss() }) { draft in
            AddFoodSheet(draft: draft, date: date)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .initial:
            hint(icon: "magnifyingglass",
                 title: "Find a food",
                 message: "Type a name and hit search. Results come from the Open Food Facts community database.")
        case .searching:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Searching…").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            hint(icon: "questionmark.circle",
                 title: "No matches",
                 message: "We couldn't find that. Try different words, scan its barcode, or add it yourself.")
        case .failed:
            hint(icon: "wifi.exclamationmark",
                 title: "Search didn't work",
                 message: "Check your connection and try again.")
        case .results:
            resultsList
        }
    }

    private var resultsList: some View {
        List(results) { product in
            Button {
                draft = makeDraft(from: product)
            } label: {
                ResultRow(product: product)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func hint(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        phase = .searching
        searchTask = Task {
            do {
                let found = try await OpenFoodFactsService.search(query: trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    results = found
                    phase = found.isEmpty ? .empty : .results
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    results = []
                    phase = .failed
                }
            }
        }
    }

    private func makeDraft(from p: OFFProduct) -> FoodDraft {
        let name = [p.brand, p.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return FoodDraft(
            name: name.isEmpty ? p.name : name,
            meal: MealTime.current(),
            servingDescription: p.servingDescription,
            quantity: 1,
            calories: p.caloriesPerServing,
            proteinG: p.proteinG,
            carbsG: p.carbsG,
            fatG: p.fatG,
            source: .search,
            barcode: p.barcode
        )
    }
}

// MARK: - Result row

private struct ResultRow: View {
    let product: OFFProduct

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(product.caloriesPerServing.rounded()))")
                    .font(Theme.number(16))
                    .foregroundStyle(Theme.calories)
                Text("kcal/serving")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
