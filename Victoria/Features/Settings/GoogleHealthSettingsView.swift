//
//  GoogleHealthSettingsView.swift
//  Victoria
//
//  Direct Fitbit connection via the Google Health API — no bridge app needed.
//  One-time setup: paste the OAuth client ID from Bryan's Google Cloud project,
//  sign in with Google, done. Data lands in the same rows Apple Health feeds.
//

import SwiftUI
import SwiftData

struct GoogleHealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var clientID: String = GoogleHealthAuth.clientID ?? ""
    @State private var isConnected: Bool = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            introSection
            if isConnected {
                connectedSection
            } else {
                setupSection
                connectSection
            }
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
        }
        .navigationTitle("Fitbit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isConnected = GoogleHealthAuth.shared.isConnected }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Label("Fitbit via Google Health", systemImage: "figure.run.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.brand)
                Text("Connects straight to your Google account to pull the Fitbit Air's sleep (with stages), resting heart rate, HRV, and detected workouts — no bridge app in between.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Theme.Space.xs)
        }
    }

    private var setupSection: some View {
        Section {
            TextField("OAuth client ID (…apps.googleusercontent.com)", text: $clientID)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: clientID) { _, newValue in
                    GoogleHealthAuth.setClientID(newValue)
                }
        } header: {
            Text("One-time setup")
        } footer: {
            Text("From your Google Cloud project: APIs & Services → Credentials → the iOS OAuth client. The client ID is public — the sign-in below is what grants access, and only to your own account.")
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                connect()
            } label: {
                HStack {
                    Label("Sign in with Google", systemImage: "person.badge.key.fill")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(isWorking || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            Text("You'll sign in on Google's own page and approve read-only access to sleep, heart metrics, and activity. Nothing is ever written back.")
        }
    }

    private var connectedSection: some View {
        Section {
            Label("Connected to Google Health", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.positive)
            if let last = GoogleHealthSync.lastSyncAt {
                LabeledContent("Last sync") {
                    Text(last.formatted(.relative(presentation: .named)))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Button {
                syncNow()
            } label: {
                HStack {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(isWorking)
            Button(role: .destructive) {
                GoogleHealthAuth.shared.disconnect()
                isConnected = false
                statusMessage = nil
                errorMessage = nil
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
                    .foregroundStyle(Theme.warning)
            }
        } footer: {
            Text("Syncs the last two weeks automatically every time the app opens. Data appears on the Today tracker card and in your sleep and recovery views.")
        }
    }

    // MARK: - Actions

    private func connect() {
        statusMessage = nil
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await GoogleHealthAuth.shared.signIn()
                isConnected = true
                // First pull right away so the connect feels alive.
                statusMessage = await GoogleHealthSync.refresh(days: 14, into: modelContext)
            } catch let error as GoogleHealthAuth.AuthError {
                if case .cancelled = error { return }   // user closed the sheet — not an error
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "Couldn't connect: \(error.localizedDescription)"
            }
        }
    }

    private func syncNow() {
        statusMessage = nil
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            statusMessage = await GoogleHealthSync.refresh(days: 14, into: modelContext)
            isConnected = GoogleHealthAuth.shared.isConnected
        }
    }
}
