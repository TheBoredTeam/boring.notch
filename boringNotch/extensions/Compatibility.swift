//
//  Compatibility.swift
//  boringNotch
//
//  Backward compatibility layer for macOS 12 (Monterey) support.
//

import SwiftUI

// MARK: - Animation Compatibility

extension Animation {
    /// Returns `.smooth` on macOS 14+, `.easeInOut` on older versions.
    static func compatibleSmooth(duration: Double = 0.35) -> Animation {
        if #available(macOS 14.0, *) {
            return .smooth(duration: duration)
        } else {
            return .easeInOut(duration: duration)
        }
    }

    /// Returns `.bouncy` on macOS 14+, standard spring on older versions.
    static func compatibleBouncy(duration: Double = 0.5, extraBounce: Double = 0.0) -> Animation {
        if #available(macOS 14.0, *) {
            return .bouncy(duration: duration, extraBounce: extraBounce)
        } else {
            return .spring(response: duration, dampingFraction: 0.7 - extraBounce * 0.2)
        }
    }
}

// MARK: - Task Sleep Compatibility

extension Task where Success == Never, Failure == Never {
    /// Sleep for specified seconds. Uses Duration on macOS 14+, nanoseconds on older.
    static func compatibleSleep(seconds: Double) async throws {
        if #available(macOS 14.0, *) {
            try await Task.sleep(for: .seconds(seconds))
        } else {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    /// Sleep for specified milliseconds. Uses Duration on macOS 14+, nanoseconds on older.
    static func compatibleSleep(milliseconds: Int) async throws {
        if #available(macOS 14.0, *) {
            try await Task.sleep(for: .milliseconds(milliseconds))
        } else {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        }
    }
}

// MARK: - View Extension Compatibility

extension View {
    /// Backward-compatible onChange that provides both old and new values.
    /// On macOS 14+, uses the new 2-parameter signature. On older versions, manually tracks the old value.
    @ViewBuilder
    func compatibleOnChange<V: Equatable>(of value: V, perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.modifier(CompatibleOnChangeModifier(value: value, action: action))
        }
    }

    /// Backward-compatible sensoryFeedback. No-op on macOS < 14.
    @ViewBuilder
    func compatibleSensoryFeedback(_ feedback: CompatibleSensoryFeedback, trigger: some Equatable) -> some View {
        if #available(macOS 14.0, *) {
            self.sensoryFeedback(feedback.systemFeedback, trigger: trigger)
        } else {
            self
        }
    }

    /// Backward-compatible contentTransition. No-op on macOS < 13.
    @ViewBuilder
    func compatibleContentTransition(_ transition: CompatibleContentTransition) -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(transition.systemTransition)
        } else {
            self
        }
    }

    /// Backward-compatible scrollIndicators. No-op on macOS < 13.
    @ViewBuilder
    func compatibleScrollIndicators(_ visibility: CompatibleScrollIndicatorVisibility) -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(visibility.systemVisibility)
        } else {
            self
        }
    }

    /// Backward-compatible safeAreaPadding. Uses regular padding on macOS < 14.
    @ViewBuilder
    func compatibleSafeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        if #available(macOS 14.0, *) {
            if let length = length {
                self.safeAreaPadding(edges, length)
            } else {
                self.safeAreaPadding(edges)
            }
        } else {
            if let length = length {
                self.padding(edges, length)
            } else {
                self.padding(edges)
            }
        }
    }
}

// MARK: - Helper Modifier for onChange Compatibility

private struct CompatibleOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let action: (V, V) -> Void

    @State private var oldValue: V

    init(value: V, action: @escaping (V, V) -> Void) {
        self.value = value
        self.action = action
        self._oldValue = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { newValue in
                action(oldValue, newValue)
                oldValue = newValue
            }
    }
}

// MARK: - Sensory Feedback Compatibility Types

enum CompatibleSensoryFeedback {
    case alignment
    case impact
    case selection
    case success
    case warning
    case error

    @available(macOS 14.0, *)
    var systemFeedback: SensoryFeedback {
        switch self {
        case .alignment: return .alignment
        case .impact: return .impact
        case .selection: return .selection
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
}

// MARK: - Content Transition Compatibility Types

enum CompatibleContentTransition {
    case interpolate
    case numericText
    case symbolEffect

    @available(macOS 14.0, *)
    var systemTransition: ContentTransition {
        switch self {
        case .interpolate: return .interpolate
        case .numericText: return .numericText()
        case .symbolEffect: return .symbolEffect
        }
    }
}

// MARK: - Scroll Indicator Visibility Compatibility

enum CompatibleScrollIndicatorVisibility {
    case automatic
    case visible
    case hidden
    case never

    @available(macOS 13.0, *)
    var systemVisibility: ScrollIndicatorVisibility {
        switch self {
        case .automatic: return .automatic
        case .visible: return .visible
        case .hidden: return .hidden
        case .never: return .never
        }
    }
}

// MARK: - Transition Compatibility

extension AnyTransition {
    /// Returns `.blurReplace` on macOS 14+, `.opacity` on older versions.
    static var compatibleBlurReplace: AnyTransition {
        if #available(macOS 14.0, *) {
            return .blurReplace
        } else {
            return .opacity
        }
    }
}

// MARK: - Scroll Content Background Compatibility

extension View {
    /// Backward-compatible scrollContentBackground. No-op on macOS < 13.
    @ViewBuilder
    func compatibleScrollContentBackground(_ visibility: CompatibleBackgroundVisibility) -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(visibility.systemVisibility)
        } else {
            self
        }
    }
}

enum CompatibleBackgroundVisibility {
    case automatic
    case visible
    case hidden

    @available(macOS 13.0, *)
    var systemVisibility: Visibility {
        switch self {
        case .automatic: return .automatic
        case .visible: return .visible
        case .hidden: return .hidden
        }
    }
}

// MARK: - List Row Separator Compatibility

extension View {
    /// Backward-compatible listRowSeparator. No-op on macOS < 13.
    @ViewBuilder
    func compatibleListRowSeparator(_ visibility: CompatibleBackgroundVisibility) -> some View {
        if #available(macOS 13.0, *) {
            self.listRowSeparator(visibility.systemVisibility)
        } else {
            self
        }
    }

    /// Backward-compatible listRowSeparatorTint. No-op on macOS < 13.
    @ViewBuilder
    func compatibleListRowSeparatorTint(_ color: Color?) -> some View {
        if #available(macOS 13.0, *) {
            self.listRowSeparatorTint(color)
        } else {
            self
        }
    }
}
