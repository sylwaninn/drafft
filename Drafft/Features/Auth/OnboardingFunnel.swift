import Foundation

/// The sign-up funnel in analytics (docs/telemetry.md): each step shown and completed with its time on
/// screen, a resumed sign-up, and the end, as counts and yes/no only, never the answers. The terms and
/// the sign-up's save report their own outcome (`TermsConsent.accept`, `ProfileSync.finish`).
/// The step and chapter ids are the Android app's, so the funnel spans both platforms.
@MainActor
final class OnboardingFunnel {
    private let openedAt = ContinuousClock.now
    private var stepShownAt = ContinuousClock.now
    private var shownIndex: Int?
    private var resumedIndex: Int?

    /// A step on screen (counted once per arrival on it).
    func shown(_ step: OnboardingView.Step, index: Int) {
        guard index != shownIndex else { return }
        shownIndex = index
        stepShownAt = .now
        let resumed = resumedIndex == index
        resumedIndex = nil
        Telemetry.track(.onboardingStepViewed(step: step.telemetryID, chapter: step.chapter.telemetryID,
                                              index: index, resumed: resumed))
    }

    /// Saved progress opened the sign-up on this step.
    func resumed(_ step: OnboardingView.Step, index: Int) {
        resumedIndex = index
        Telemetry.track(.onboardingResumed(step: step.telemetryID, index: index))
        shown(step, index: index)
    }

    /// Continue on a complete step, Skip on an optional one left empty.
    func completed(_ step: OnboardingView.Step, index: Int, skipped: Bool) {
        let seconds = Int((ContinuousClock.now - stepShownAt).components.seconds)
        Telemetry.track(.onboardingStepCompleted(step: step.telemetryID, chapter: step.chapter.telemetryID,
                                                 index: index, skipped: skipped, seconds: seconds))
    }

    /// Signed up: counts and yes/no only, never the answers themselves (gender, who to meet, lifestyle).
    func finished(_ signUp: ProfileSync.SignUp) {
        let minutes = Int((ContinuousClock.now - openedAt).components.seconds / 60)
        Telemetry.track(.onboardingCompleted(
            photos: signUp.photos.count, sports: signUp.sports.count, prompts: signUp.prompts.count,
            hasVoice: signUp.voice != nil, hasBio: !signUp.bio.isEmpty, hasIcebreaker: signUp.icebreaker != nil,
            answeredLifestyle: signUp.lifestyle.hasLifestyle, notificationsAllowed: NotificationService.shared.isAllowed,
            minutes: minutes))
    }
}

extension OnboardingView.Step {
    /// The step's id in analytics (`show_me`), the same on Android.
    var telemetryID: String {
        String(describing: self).replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression)
            .lowercased()
    }
}

extension OnboardingView.Step.Chapter {
    /// The chapter's id in analytics (`you`), the same on Android.
    var telemetryID: String { String(describing: self) }
}
