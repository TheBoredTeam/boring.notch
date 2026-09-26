//
//  AISessionsPixelTests.swift
//  boringNotchTests
//

import AppKit
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class AISessionsPixelTests: XCTestCase {
    func testSessionsPanelPaintsSampleContent() throws {
        let now = Date()
        let sessions = [
            AISessionRecord(
                id: "codex:sample-1", source: .codex,
                projectName: "Project Alpha", status: .working,
                lastActivity: now, latestMessage: nil,
                isDesktopSession: true, cwd: "/tmp/Project Alpha",
                latestPrompt: "Investigate the build failure",
                latestReply: nil, terminalBundleID: nil,
                windowTitle: nil, currentTool: "Read"
            ),
            AISessionRecord(
                id: "claude:sample-2", source: .claude,
                projectName: "Website", status: .idle,
                lastActivity: now.addingTimeInterval(-90),
                latestMessage: "The tests passed and the changes are ready for review.",
                isDesktopSession: false, cwd: "/tmp/Website",
                latestPrompt: "Summarize the latest changes",
                latestReply: "The tests passed and the changes are ready for review.",
                terminalBundleID: nil, windowTitle: nil, currentTool: nil
            ),
        ]
        let view = NotchAISessionsView(previewSessions: sessions)
            .environmentObject(BoringViewModel(camera: CameraModel()))
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: 640, height: 320)
            .background(Color.black)
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 320)
        hostingView.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 8_000)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "AI sessions panel with sample data"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let output = ProcessInfo.processInfo.environment["AI_SESSIONS_SCREENSHOT_PATH"] {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }
}
