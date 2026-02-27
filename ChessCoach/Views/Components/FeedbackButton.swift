import SwiftUI

/// In-app feedback form that submits directly to GitHub Issues.
struct FeedbackFormView: View {
    let screen: String
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var category = "general"
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What kind of feedback?") {
                    Picker("Category", selection: $category) {
                        Text("General").tag("general")
                        Text("Bug Report").tag("bug")
                        Text("Feature Request").tag("feature")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Your feedback") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Send") {
                            submitFeedback()
                        }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .overlay {
                if submitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Thanks for your feedback!")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submitFeedback() {
        isSubmitting = true
        errorMessage = nil
        let payload = FeedbackService.FeedbackPayload(
            screen: screen,
            category: category,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Task {
            do {
                try await FeedbackService.shared.submit(payload)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    submitted = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

/// Reusable feedback button that opens the in-app feedback form.
/// Always visible (used in Settings). For other screens, use FeedbackToolbarButton.
struct FeedbackButton: View {
    var screen: String = ""
    @State private var showForm = false

    var body: some View {
        Button {
            showForm = true
        } label: {
            Label("Report Bug", systemImage: "ladybug.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showForm) {
            FeedbackFormView(screen: screen)
        }
    }
}

/// Toolbar-friendly icon-only version for NavigationStack screens.
/// Only visible during beta (AppConfig.isBeta). In release, feedback is Settings-only.
struct FeedbackToolbarButton: View {
    var screen: String = ""
    @State private var showForm = false

    var body: some View {
        if AppConfig.isBeta {
            Button {
                showForm = true
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showForm) {
                FeedbackFormView(screen: screen)
            }
        }
    }
}
