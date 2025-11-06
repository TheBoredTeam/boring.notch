// ThirdPartyShims.swift
// Temporary shims to allow project to compile without optional third-party dependencies.
// TODO: Replace these with real Swift Package dependencies and remove shims.

import Foundation
import SwiftUI

// MARK: - Defaults
#if canImport(Defaults)
import Defaults
#else
// Minimal shim for Defaults
public enum DefaultsShim {
    public static func get<T>(_ key: String, default defaultValue: T) -> T { defaultValue }
}
#endif

// MARK: - OrderedCollections
#if canImport(OrderedCollections)
import OrderedCollections
#else
public struct OrderedDictionary<Key: Hashable, Value> {
    public init() {}
}
public struct OrderedSet<Element: Hashable> {
    public init() {}
}
#endif

// MARK: - Lottie
#if canImport(Lottie)
import Lottie
#else
public struct LottieAnimationView: View {
    public init(name: String) {}
    public var body: some View { EmptyView() }
}
#endif

// MARK: - LottieUI
#if canImport(LottieUI)
import LottieUI
#else
public struct LottieView: View {
    public init(name: String, loopMode: Int = 0) {}
    public var body: some View { EmptyView() }
}
#endif

// MARK: - Sparkle (macOS only)
#if canImport(Sparkle)
import Sparkle
#else
#if os(macOS)
public final class SUUpdater: ObservableObject {
    public static let shared = SUUpdater()
    public func checkForUpdates(_ sender: Any?) {}
}
#endif
#endif

// MARK: - LaunchAtLogin (macOS only)
#if canImport(LaunchAtLogin)
import LaunchAtLogin
#else
#if os(macOS)
public enum LaunchAtLogin {
    public static var isEnabled: Bool { get { false } set { _ = newValue } }
}
#endif
#endif

// MARK: - SwiftUIIntrospect
#if canImport(SwiftUIIntrospect)
import SwiftUIIntrospect
#else
// No-op modifiers to keep call sites compiling if used with conditional availability
extension View {
    public func introspect(_ any: Any? = nil) -> some View { self }
}
#endif

// MARK: - KeyboardShortcuts (macOS only)
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#else
#if os(macOS)
public enum KeyboardShortcuts {
    public struct Name: Hashable, Equatable, RawRepresentable { public var rawValue: String; public init(_ rawValue: String) { self.rawValue = rawValue }; public init(rawValue: String) { self.rawValue = rawValue } }
    public struct Shortcut { public init(_ name: Name) {} }
    public static func onKeyUp(for name: Name, action: @escaping () -> Void) {}
}
#endif
#endif

// MARK: - TheBoringWorkerNotifier
#if canImport(TheBoringWorkerNotifier)
import TheBoringWorkerNotifier
#else
public enum TheBoringWorkerNotifier {
    public static func notify(_ message: String) { /* no-op */ }
}
#endif

// MARK: - MacroVisionKit
#if canImport(MacroVisionKit)
import MacroVisionKit
#else
public enum MacroVisionKit {
    public struct Session { public init() {} }
}
#endif
