//
//  OnboardingView.swift
//  Kairo
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation
import Defaults
import Sparkle

enum OnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case audioCapturePermission
    case accessibilityPermission
    case musicPermission
    case softwareUpdatePermission
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let updater: SPUUpdater?
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "Kairo includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "Kairo can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                                await requestCalendarPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .remindersPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .remindersPermission
                            }
                    }
                )
                .transition(.opacity)

                case .remindersPermission:
                    PermissionRequestView(
                        icon: Image(systemName: "checklist"),
                        title: "Enable Reminders Access",
                        description: "Kairo can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                        privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                        onAllow: {
                            Task {
                                await requestRemindersPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = nextStepAfterReminders()
                                }
                            }
                        },
                        onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = nextStepAfterReminders()
                            }
                        }
                    )
                    .transition(.opacity)

            case .audioCapturePermission:
                PermissionRequestView(
                    icon: Image(systemName: "waveform"),
                    title: "Enable Real-Time Audio",
                    description: "Boring Notch can analyze the audio playing from your music app to draw a live FFT waveform in the notch, with only a minimal impact on CPU usage.",
                    privacyNote: "Audio is processed locally for the visualizer and never recorded, stored, or shared.",
                    onAllow: {
                        Task {
                            let granted = await requestAudioCapturePermission()
                            if granted {
                                Defaults[.realtimeAudioWaveform] = true
                            }
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .accessibilityPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the Kairo HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            KairoViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        _ = try? await calendarService.requestAccess(to: .event)
    }

    func requestRemindersPermission() async {
        _ = try? await calendarService.requestAccess(to: .reminder)
    }

    func requestAudioCapturePermission() async -> Bool {
        await AudioCaptureManager.shared.requestAudioCapturePermission()
    }

    func nextStepAfterReminders() -> OnboardingStep {
        if #available(macOS 14.2, *) {
            return .audioCapturePermission
        }
        return .accessibilityPermission
    }
    
}

struct SoftwareUpdatePermissionView: View {
    let updater: SPUUpdater?
    let onContinue: () -> Void

    @State private var automaticallyChecksForUpdates = true
    @State private var automaticallyDownloadsUpdates = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.effectiveAccent)

            Text("Keep Boring Notch Updated")
                .font(.title)
                .fontWeight(.semibold)

            Text("Boring Notch can check for updates in the background. You can still check manually from the menu bar at any time.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 34)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Check for updates automatically", isOn: $automaticallyChecksForUpdates)

                Toggle("Download and install updates automatically", isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .opacity(automaticallyChecksForUpdates ? 1 : 0.45)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 44)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button("Continue") {
                applyUpdatePreference(
                    checksAutomatically: automaticallyChecksForUpdates,
                    downloadsAutomatically: automaticallyChecksForUpdates && automaticallyDownloadsUpdates
                )
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onChange(of: automaticallyChecksForUpdates) { _, enabled in
            if !enabled {
                automaticallyDownloadsUpdates = false
            }
        }
    }

    private func applyUpdatePreference(checksAutomatically: Bool, downloadsAutomatically: Bool) {
        guard let updater else {
            UserDefaults.standard.set(checksAutomatically, forKey: "SUEnableAutomaticChecks")
            UserDefaults.standard.set(downloadsAutomatically, forKey: "SUAutomaticallyUpdate")
            return
        }

        updater.automaticallyChecksForUpdates = checksAutomatically
        updater.automaticallyDownloadsUpdates = downloadsAutomatically
    }
}
