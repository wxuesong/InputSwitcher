import AppKit
import XCTest
@testable import InputSwitcher

final class RuleStoreLogicTests: XCTestCase {
    private var hostApplicationBundle: Bundle? {
        let testBundleURL = Bundle(for: Self.self).bundleURL
        let appBundleURL = testBundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return Bundle(url: appBundleURL)
    }

    func testAdaptiveIconResourcesAreAvailable() async {
        await MainActor.run {
            guard let appBundle = self.hostApplicationBundle else {
                XCTFail("Unable to locate the host application bundle")
                return
            }

            XCTAssertNotNil(appBundle.image(forResource: "InputSwitcher"))
            XCTAssertNotNil(appBundle.image(forResource: "MenuBarIcon_dark"))
            XCTAssertTrue(
                AdaptiveIconAssets.menuBarTemplateImage(in: appBundle)?.isTemplate == true
            )
            XCTAssertFalse(
                AdaptiveIconAssets.applicationIcon(isDark: true, in: appBundle)
                    .representations.isEmpty
            )
        }
    }

    func testPrivacyManifestMatchesDisclosure() throws {
        guard let manifestURL = hostApplicationBundle?.url(
            forResource: "PrivacyInfo",
            withExtension: "xcprivacy"
        ) else {
            XCTFail("PrivacyInfo.xcprivacy is missing from the application bundle")
            return
        }

        let data = try Data(contentsOf: manifestURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let manifest = object as? [String: Any] else {
            XCTFail("PrivacyInfo.xcprivacy is not a dictionary")
            return
        }

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.count, 0)

        let accessedAPIs = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        XCTAssertEqual(accessedAPIs.count, 1)
        XCTAssertEqual(
            accessedAPIs.first?["NSPrivacyAccessedAPIType"] as? String,
            "NSPrivacyAccessedAPICategoryUserDefaults"
        )
        XCTAssertEqual(
            accessedAPIs.first?["NSPrivacyAccessedAPITypeReasons"] as? [String],
            ["CA92.1"]
        )
    }

    func testReopenRequestsSettingsWindow() async {
        await MainActor.run {
            var didRequestSettings = false
            let observer = NotificationCenter.default.addObserver(
                forName: .inputSwitcherOpenSettingsRequested,
                object: nil,
                queue: nil
            ) { _ in
                didRequestSettings = true
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            let handled = AppDelegate().applicationShouldHandleReopen(
                NSApplication.shared,
                hasVisibleWindows: false
            )

            XCTAssertTrue(handled)
            XCTAssertTrue(didRequestSettings)
        }
    }

    func testGlobalShortcutsDefaultToDisabled() {
        XCTAssertEqual(GlobalShortcutOption.defaultEnabled, .disabled)
        XCTAssertEqual(GlobalShortcutOption.defaultGlobalLock, .disabled)
        XCTAssertEqual(
            GlobalShortcutOption.option(for: "unknown", fallback: .defaultEnabled),
            .disabled
        )
    }

    func testImportedRulesRejectDuplicateBundleIdentifiers() async {
        await MainActor.run {
            let rules = [
                Rule(bundleID: "com.example.app", appName: "One", inputSourceID: "source.one"),
                Rule(bundleID: "com.example.app", appName: "Two", inputSourceID: "source.two")
            ]
            XCTAssertNil(RuleStore.validatedImportedRules(rules))
        }
    }

    func testImportedRulesRejectEmptyRequiredFields() async {
        await MainActor.run {
            XCTAssertNil(
                RuleStore.validatedImportedRules([
                    Rule(bundleID: " ", appName: "App", inputSourceID: "source.one")
                ])
            )
            XCTAssertNil(
                RuleStore.validatedImportedRules([
                    Rule(bundleID: "com.example.app", appName: "App", inputSourceID: " ")
                ])
            )
        }
    }

    func testImportedRulesAreNormalizedAndDoNotTrustSyncedMetadata() async {
        await MainActor.run {
            let imported = Rule(
                bundleID: " com.example.app ",
                appName: " ",
                inputSourceID: " source.one ",
                isLocked: true,
                syncedInputSourceID: "untrusted.source",
                syncedInputSourceName: "Untrusted",
                isAutoLearned: true
            )
            let result = RuleStore.validatedImportedRules([imported])
            XCTAssertEqual(result?.first?.bundleID, "com.example.app")
            XCTAssertEqual(result?.first?.appName, "com.example.app")
            XCTAssertEqual(result?.first?.inputSourceID, "source.one")
            XCTAssertEqual(result?.first?.isLocked, true)
            XCTAssertNil(result?.first?.syncedInputSourceID)
            XCTAssertNil(result?.first?.syncedInputSourceName)
            XCTAssertEqual(result?.first?.isAutoLearned, false)
        }
    }

    func testStoredRulesAreNormalizedAndDeduplicated() async {
        await MainActor.run {
            let stored = [
                Rule(
                    bundleID: " com.example.app ",
                    appName: " ",
                    inputSourceID: " source.one ",
                    isLocked: true,
                    syncedInputSourceID: "cloud.source",
                    syncedInputSourceName: "Cloud Source",
                    isAutoLearned: true
                ),
                Rule(bundleID: "com.example.app", appName: "Duplicate", inputSourceID: "source.two"),
                Rule(bundleID: " ", appName: "Invalid", inputSourceID: "source.three")
            ]

            let result = RuleStore.sanitizedStoredRules(stored)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0].bundleID, "com.example.app")
            XCTAssertEqual(result[0].appName, "com.example.app")
            XCTAssertEqual(result[0].inputSourceID, "source.one")
            XCTAssertTrue(result[0].isLocked)
            XCTAssertEqual(result[0].syncedInputSourceID, "cloud.source")
            XCTAssertEqual(result[0].syncedInputSourceName, "Cloud Source")
            XCTAssertTrue(result[0].isAutoLearned)
        }
    }

    func testImportedRulesRejectExcessiveRuleCount() async {
        await MainActor.run {
            let rules = (0...RuleStore.maximumRuleCount).map { index in
                Rule(
                    bundleID: "com.example.app\(index)",
                    appName: "App \(index)",
                    inputSourceID: "source.one"
                )
            }
            XCTAssertNil(RuleStore.validatedImportedRules(rules))
        }
    }

    func testMenuRuleCountNormalization() async {
        await MainActor.run {
            XCTAssertEqual(RuleStore.normalizedMenuRuleCount(-1), 0)
            XCTAssertEqual(RuleStore.normalizedMenuRuleCount(1), 5)
            XCTAssertEqual(RuleStore.normalizedMenuRuleCount(8), 10)
            XCTAssertEqual(RuleStore.normalizedMenuRuleCount(99), 15)
        }
    }

    func testFreeUserCanActivateOneRuleLock() async {
        await MainActor.run {
            let unlockedRules = [
                Rule(bundleID: "com.example.one", appName: "One", inputSourceID: "source.one"),
                Rule(bundleID: "com.example.two", appName: "Two", inputSourceID: "source.two")
            ]
            XCTAssertTrue(
                RuleStore.canEnableRuleLock(
                    bundleID: "com.example.one",
                    rules: unlockedRules,
                    isPro: false
                )
            )

            let oneLockedRule = [
                Rule(bundleID: "com.example.one", appName: "One", inputSourceID: "source.one", isLocked: true),
                Rule(bundleID: "com.example.two", appName: "Two", inputSourceID: "source.two")
            ]

            XCTAssertTrue(
                RuleStore.isRuleLockActive(
                    bundleID: "com.example.one",
                    rules: oneLockedRule,
                    isPro: false
                )
            )
            XCTAssertFalse(
                RuleStore.canEnableRuleLock(
                    bundleID: "com.example.two",
                    rules: oneLockedRule,
                    isPro: false
                )
            )
        }
    }

    func testProUserCanActivateMultipleRuleLocks() async {
        await MainActor.run {
            let rules = [
                Rule(bundleID: "com.example.one", appName: "One", inputSourceID: "source.one", isLocked: true),
                Rule(bundleID: "com.example.two", appName: "Two", inputSourceID: "source.two", isLocked: true)
            ]

            XCTAssertTrue(
                RuleStore.isRuleLockActive(
                    bundleID: "com.example.two",
                    rules: rules,
                    isPro: true
                )
            )
            XCTAssertTrue(
                RuleStore.canEnableRuleLock(
                    bundleID: "com.example.two",
                    rules: rules,
                    isPro: true
                )
            )
        }
    }

    func testFreeUserCannotUseLockedRuleBeyondFreeRuleLimit() async {
        await MainActor.run {
            var rules = (0..<PurchaseManager.freeRuleLimit).map { index in
                Rule(
                    bundleID: "com.example.\(index)",
                    appName: "App \(index)",
                    inputSourceID: "source.one"
                )
            }
            rules.append(
                Rule(
                    bundleID: "com.example.outside-limit",
                    appName: "Outside Limit",
                    inputSourceID: "source.one",
                    isLocked: true
                )
            )

            XCTAssertFalse(
                RuleStore.isRuleLockActive(
                    bundleID: "com.example.outside-limit",
                    rules: rules,
                    isPro: false
                )
            )
            XCTAssertFalse(
                RuleStore.canEnableRuleLock(
                    bundleID: "com.example.outside-limit",
                    rules: rules,
                    isPro: false
                )
            )
        }
    }

    func testVersionVectorOrdering() async {
        await MainActor.run {
            XCTAssertEqual(
                RuleStore.compareVersionVectors(["A": 1], ["A": 1]),
                .equal
            )
            XCTAssertEqual(
                RuleStore.compareVersionVectors(["A": 2, "B": 1], ["A": 1, "B": 1]),
                .localDominates
            )
            XCTAssertEqual(
                RuleStore.compareVersionVectors(["A": 1], ["A": 1, "B": 1]),
                .remoteDominates
            )
            XCTAssertEqual(
                RuleStore.compareVersionVectors(["A": 2, "B": 1], ["A": 1, "B": 2]),
                .concurrent
            )
        }
    }
}
