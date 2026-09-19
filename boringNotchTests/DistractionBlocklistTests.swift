//
//  DistractionBlocklistTests.swift
//  boringNotchTests
//
//  Host matching is the part of the blocker that fails quietly: too loose and
//  it blocks sites the user never listed, too strict and it misses the
//  subdomain they actually browse. Both sides of that line are pinned here.
//

import XCTest

@testable import boringNotch

final class DistractionBlocklistTests: XCTestCase {

    private let reddit = BlockedSite(host: "reddit.com")

    // MARK: - Host matching

    func testMatchesTheHostAndItsSubdomains() {
        for host in ["reddit.com", "www.reddit.com", "old.reddit.com", "a.b.reddit.com"] {
            XCTAssertTrue(reddit.matches(host: host), host)
        }
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(reddit.matches(host: "OLD.Reddit.COM"))
    }

    /// A plain `contains` or `hasSuffix` would accept all of these. The label
    /// boundary is the whole point of the rule.
    func testDoesNotMatchLookalikeHosts() {
        for host in ["notreddit.com", "myreddit.com", "reddit.com.evil.org", "reddit.org", "com", "xreddit.com"] {
            XCTAssertFalse(reddit.matches(host: host), host)
        }
    }

    // MARK: - Parsing what the user typed

    func testNormalizesUserInput() {
        let cases = [
            ("reddit.com", "reddit.com"),
            ("www.reddit.com", "reddit.com"),
            ("https://www.reddit.com/r/all", "reddit.com"),
            ("HTTP://Reddit.COM", "reddit.com"),
            ("  reddit.com/  ", "reddit.com"),
            ("reddit.com:8080", "reddit.com"),
            ("reddit.com/r/all?sort=new#top", "reddit.com"),
            ("user:secret@reddit.com/x", "reddit.com"),
            ("news.ycombinator.com", "news.ycombinator.com"),
            ("sub.domain.example.co.uk", "sub.domain.example.co.uk")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(BlockedSite(userInput: input)?.host, expected, input)
        }
    }

    /// "www.reddit.com" and "reddit.com" must not both be storable — the
    /// subdomain rule already covers the first, and having both in the list
    /// looks like a bug to the user.
    func testWWWIsStrippedSoTheListHasNoDuplicates() {
        XCTAssertEqual(BlockedSite(userInput: "www.reddit.com"), BlockedSite(userInput: "reddit.com"))
    }

    func testRejectsInputThatIsNotAHost() {
        for input in ["", "   ", "localhost", "not a host", "///", "https://", "reddit"] {
            XCTAssertNil(BlockedSite(userInput: input), input)
        }
    }

    // MARK: - App rules

    func testBlocksListedAppsIncludingHelperProcesses() {
        let list = DistractionBlocklist(
            apps: [BlockedApp(bundleID: "com.hnc.Discord")], sites: [], blockApps: true, blockSites: false
        )

        XCTAssertTrue(list.shouldBlockApp(bundleID: "com.hnc.Discord"))
        XCTAssertTrue(list.shouldBlockApp(bundleID: "com.hnc.Discord.helper"), "helper processes resolve to the parent")
        XCTAssertFalse(list.shouldBlockApp(bundleID: "com.apple.finder"))
    }

    /// Hiding the whole browser because one tab is Reddit takes away the
    /// user's browser. Sites are handled per tab instead.
    func testBrowsersAreNeverHiddenAsApps() {
        let list = DistractionBlocklist(
            apps: [BlockedApp(bundleID: "com.apple.Safari"), BlockedApp(bundleID: "com.google.Chrome")],
            sites: [], blockApps: true, blockSites: false
        )

        XCTAssertFalse(list.shouldBlockApp(bundleID: "com.apple.Safari"))
        XCTAssertFalse(list.shouldBlockApp(bundleID: "com.google.Chrome"))
        XCTAssertFalse(list.shouldBlockApp(bundleID: "com.apple.WebKit.WebContent"), "nor a web content process")
    }

    // MARK: - Site rules

    func testBlocksListedSitesOverHTTPAndHTTPS() {
        let list = DistractionBlocklist(apps: [], sites: [reddit], blockApps: false, blockSites: true)

        XCTAssertTrue(list.shouldBlockSite(urlString: "https://old.reddit.com/r/all"))
        XCTAssertTrue(list.shouldBlockSite(urlString: "http://reddit.com"))
        XCTAssertFalse(list.shouldBlockSite(urlString: "https://notreddit.com"))
    }

    /// The blocker's only action is to navigate the tab away. It must never do
    /// that to a local file, a blank tab, or an app's own scheme.
    func testNeverActsOnNonWebSchemes() {
        let list = DistractionBlocklist(apps: [], sites: [reddit], blockApps: false, blockSites: true)

        for url in [
            "file:///Users/me/reddit.com.html",
            "about:blank",
            "javascript:void(0)",
            "data:text/html,reddit.com",
            "ftp://reddit.com"
        ] {
            XCTAssertFalse(list.shouldBlockSite(urlString: url), url)
        }
    }

    func testMalformedURLsAreIgnored() {
        let list = DistractionBlocklist(apps: [], sites: [reddit], blockApps: false, blockSites: true)
        XCTAssertFalse(list.shouldBlockSite(urlString: ""))
    }

    // MARK: - Switches

    func testSwitchesGateEachRuleIndependently() {
        var list = DistractionBlocklist(
            apps: [BlockedApp(bundleID: "com.hnc.Discord")], sites: [reddit],
            blockApps: true, blockSites: true
        )
        XCTAssertTrue(list.shouldBlockApp(bundleID: "com.hnc.Discord"))
        XCTAssertTrue(list.shouldBlockSite(urlString: "https://reddit.com"))

        list.blockApps = false
        XCTAssertFalse(list.shouldBlockApp(bundleID: "com.hnc.Discord"))
        XCTAssertTrue(list.shouldBlockSite(urlString: "https://reddit.com"), "sites are unaffected")

        list.blockSites = false
        XCTAssertFalse(list.shouldBlockSite(urlString: "https://reddit.com"))
    }

    /// `isEmpty` is what stops the blocker arming with nothing to do — an
    /// armed blocker polls the front browser every two seconds.
    func testIsEmptyWhenThereIsNothingToEnforce() {
        XCTAssertTrue(DistractionBlocklist().isEmpty)
        XCTAssertTrue(
            DistractionBlocklist(apps: [BlockedApp(bundleID: "x")], sites: [reddit], blockApps: false, blockSites: false).isEmpty,
            "switches off means nothing to enforce"
        )
        XCTAssertTrue(
            DistractionBlocklist(apps: [], sites: [], blockApps: true, blockSites: true).isEmpty,
            "switches on but both lists empty"
        )
        XCTAssertFalse(
            DistractionBlocklist(apps: [], sites: [reddit], blockApps: false, blockSites: true).isEmpty
        )
    }

    // MARK: - Shipped defaults

    func testSuggestedSitesAreAlreadyNormalized() {
        for site in DistractionBlocklist.suggestedSites {
            XCTAssertEqual(BlockedSite(userInput: site.host)?.host, site.host, site.host)
        }
    }

    func testNoSuggestedAppIsABrowser() {
        for app in DistractionBlocklist.suggestedApps {
            XCTAssertFalse(
                DistractionBlocklist.browserBundleIDs.contains(app.bundleID.lowercased()),
                "\(app.bundleID) would be silently ignored by the app rule"
            )
        }
    }
}
