import AppKit
import SwiftUI

struct LicenseOnboardingView: View {
    @ObservedObject var license: PolarLicenseModel
    let isPreview: Bool
    let onUnlocked: () -> Void
    let onExitPreview: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isKeyFocused: Bool
    @State private var licenseKey = ""
    @State private var isHeaderVisible = false
    @State private var isFormVisible = false
    @State private var isPreviewValidating = false
    @State private var isComplete = false
    @State private var activationTask: Task<Void, Never>?

    private var isValidating: Bool { isPreview ? isPreviewValidating : license.isValidating }
    private var canActivate: Bool {
        !isValidating && !isComplete && (isPreview || license.configuration.isConfigured)
            && !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Group {
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.green)
                    } else {
                        Image(nsImage: BrowserAppIcon.image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 40, height: 40)
                .contentTransition(.opacity)

                Text(isComplete ? "You’re all set." : "Welcome to Notch Browser")
                    .font(.system(size: 23, weight: .semibold))
                    .padding(.top, 12)

                Text(isComplete ? "Your browser is ready in the notch." : "A little browser. Right where you need it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)
            }
            .opacity(isHeaderVisible ? 1 : 0)
            .offset(y: isHeaderVisible || reduceMotion ? 0 : -6)
            .padding(.top, 18)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "key")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                    SecureField("Paste your license key", text: $licenseKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .textContentType(.password)
                        .focused($isKeyFocused)
                        .accessibilityLabel("License key")
                        .onSubmit(activate)
                        .disabled(isValidating || isComplete)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(isKeyFocused ? Color.white.opacity(0.4) : Color.white.opacity(0.12))
                }

                Button(action: activate) {
                    HStack(spacing: 8) {
                        if isValidating {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isComplete ? "Unlocked" : isValidating ? "Checking license…" : "Unlock Notch Browser")
                            .font(.system(size: 13, weight: .semibold))
                        if !isValidating && !isComplete {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color(red: 0.22, green: 0.44, blue: 0.96).opacity(canActivate || isValidating || isComplete ? 1 : 0.45),
                                in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(!canActivate)
                .accessibilityLabel(isPreview ? "Preview license activation" : "Unlock Notch Browser")
            }
            .padding(.top, 22)
            .opacity(isFormVisible ? 1 : 0)
            .offset(y: isFormVisible || reduceMotion ? 0 : -5)
            .allowsHitTesting(isFormVisible)
            .accessibilityHidden(!isFormVisible)

            status
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 38, alignment: .top)
                .padding(.top, 8)
                .opacity(isFormVisible ? 1 : 0)

            Spacer(minLength: 4)

            VStack(spacing: 5) {
                if isPreview {
                    Button("Exit preview", action: onExitPreview)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                    Text("Debug preview · Your saved license stays untouched")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    if let checkoutURL = license.configuration.checkoutURL {
                        Button {
                            NSWorkspace.shared.open(checkoutURL)
                        } label: {
                            Text("Get a license · $5 once")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Already purchased? Your key is in your Polar email.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .opacity(isFormVisible ? 1 : 0)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 440)
        .frame(height: 366)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(.black)
        .preferredColorScheme(.dark)
        .task {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
                isHeaderVisible = true
            }
            if !reduceMotion { try? await Task.sleep(nanoseconds: 180_000_000) }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) {
                isFormVisible = true
            }
        }
        .onDisappear { activationTask?.cancel() }
    }

    @ViewBuilder
    private var status: some View {
        if isComplete {
            Text(isPreview ? "Preview complete. No license was checked or saved." : "License verified. Opening your browser…")
                .foregroundStyle(.white.opacity(0.55))
        } else if isPreview {
            Text("Enter any test key to preview the unlock animation.")
                .foregroundStyle(.white.opacity(0.45))
        } else if let message = license.message, !license.isValidating {
            Text(message)
                .foregroundStyle(license.messageIsError ? Color(red: 1, green: 0.48, blue: 0.45) : Color.white.opacity(0.55))
                .accessibilityLabel(message)
        }
    }

    private func activate() {
        guard canActivate else { return }
        isKeyFocused = false
        activationTask = Task { @MainActor in
            let activated: Bool
            if isPreview {
                isPreviewValidating = true
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { return }
                isPreviewValidating = false
                activated = true
            } else {
                activated = await license.activate(licenseKey)
            }
            guard !Task.isCancelled, activated else { return }
            licenseKey = ""
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isComplete = true
            }
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            onUnlocked()
        }
    }
}
