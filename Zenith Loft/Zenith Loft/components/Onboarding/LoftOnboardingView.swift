import SwiftUI
import AVFoundation

enum LoftOnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case musicPermission
    case finished
}

private let loftCalendarService = LoftCalendarService()

struct LoftOnboardingView: View {
    @State var step: LoftOnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                LoftWelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                LoftPermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "Loft includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
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
                LoftPermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "Loft can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
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
                LoftPermissionRequestView(
                    icon: Image(systemName: "checklist"),
                    title: "Enable Reminders Access",
                    description: "Loft can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                    privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                    onAllow: {
                        Task {
                            await requestRemindersPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
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
                LoftMusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                LoftOnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        _ = try? await loftCalendarService.requestAccess(to: .event)
    }

    func requestRemindersPermission() async {
        _ = try? await loftCalendarService.requestAccess(to: .reminder)
    }
}
