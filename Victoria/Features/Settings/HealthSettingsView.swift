//
//  HealthSettingsView.swift
//  Victoria
//
//  Optional Apple Health sync settings: connect, then import weigh-ins.
//

import SwiftUI
import SwiftData
import HealthKit

struct HealthSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext

    /// All local weigh-ins, used to compute which HealthKit UUIDs we already have
    /// so we never import the same sample twice.
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    private let health = HealthKitService.shared

    // UI state
    @State private var isConnecting = false
    @State private var isImporting = false
    @State private var isConnected = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var existingHealthKitUUIDs: Set<String> {
        Set(weights.compactMap { $0.healthKitUUID })
    }

    var body: some View {
        Form {
            // MARK: Intro
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                    Text("Syncing with Apple Health is completely optional. Connect it to pull in weigh-ins from your other apps and scales, all in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Space.xs)
            }

            // MARK: Connect
            Section {
                Button {
                    connect()
                } label: {
                    HStack {
                        Label(
                            isConnected ? "Apple Health Connected" : "Connect Apple Health",
                            systemImage: isConnected ? "checkmark.circle.fill" : "heart.text.square"
                        )
                        Spacer()
                        if isConnecting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isConnecting || !HealthKitService.isAvailable)
            } footer: {
                Text("You'll be asked to allow Victoria to read and save weight. You can change this anytime in the Health app.")
            }

            // MARK: Import
            Section {
                Button {
                    importFromHealth()
                } label: {
                    HStack {
                        Label("Import weigh-ins from Health", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isImporting || !HealthKitService.isAvailable)
            } footer: {
                Text("Brings in weight entries from the last year that aren't already in Victoria.")
            }

            // MARK: Status / errors
            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.positive)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                }
            }

            // MARK: Availability / Simulator note
            Section {
                if !HealthKitService.isAvailable {
                    Text("Apple Health isn't available on this device, so syncing is turned off here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Heads up: on the Simulator, Apple Health support is limited and may not return any data. Everything works as expected on a real iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func connect() {
        statusMessage = nil
        errorMessage = nil
        isConnecting = true

        Task {
            defer { isConnecting = false }
            do {
                try await health.requestAuthorization()
                isConnected = true
                statusMessage = "Apple Health is connected. You can import your weigh-ins below."
            } catch {
                isConnected = false
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    private func importFromHealth() {
        statusMessage = nil
        errorMessage = nil
        isImporting = true

        // Snapshot the known UUIDs before the async work begins.
        let knownUUIDs = existingHealthKitUUIDs

        Task {
            defer { isImporting = false }
            do {
                let count = try await health.importRecent(
                    into: modelContext,
                    existingHealthKitUUIDs: knownUUIDs
                )
                if count > 0 {
                    // Persist the inserted entries.
                    try? modelContext.save()
                }
                switch count {
                case 0:
                    statusMessage = "You're all caught up — no new weigh-ins to import."
                case 1:
                    statusMessage = "Imported 1 weigh-in from Apple Health."
                default:
                    statusMessage = "Imported \(count) weigh-ins from Apple Health."
                }
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    /// Turns any error into a kind, user-readable message.
    private func friendlyMessage(for error: Error) -> String {
        if let hkError = error as? HealthKitError, let description = hkError.errorDescription {
            return description
        }
        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "We couldn't reach Apple Health right now. \(description)"
    }
}
