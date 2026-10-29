//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Foundation
import Testing
@testable import VoiceInk

struct VoiceInkTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test @MainActor func localSourceBuildHasFullAccess() {
        #if LOCAL_BUILD
            let license = LicenseViewModel.shared
            #expect(license.isLicensed)
            #expect(license.hasVerifiedLicense)
            #expect(license.canUseApp)
            #expect(license.usageRestrictionMessage == nil)
            #expect(license.diagnosticLicenseStatus == "Local Source Build (Full Access)")
        #endif
    }

    @Test @MainActor func localSourceBuildResumesPastActivation() throws {
        #if LOCAL_BUILD
            let suiteName = "VoiceInkTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.set(OnboardingStage.license.rawValue, forKey: OnboardingStorageKeys.stage)

            let coordinator = OnboardingCoordinator(defaults: defaults)
            #expect(coordinator.stage == .trust)
            #expect(coordinator.currentStepNumber == coordinator.totalStepCount)

            defaults.removePersistentDomain(forName: suiteName)
        #endif
    }

}
