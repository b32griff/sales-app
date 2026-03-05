import SwiftUI
import SwiftData

@main
struct ToneCoachApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // Migrate stale dB defaults from old versions.
        // Old defaults were -25 to -10 (unrealistic for phone mic).
        // If user has these old values, reset to calibrated range.
        let defaults = UserDefaults.standard
        let currentMin = defaults.double(forKey: "targetDBMin")
        let currentMax = defaults.double(forKey: "targetDBMax")
        if currentMin > -30 || currentMax > -5 {
            defaults.set(-55.0, forKey: "targetDBMin")
            defaults.set(-30.0, forKey: "targetDBMax")
            print("[ToneCoach] Migrated stale dB defaults → -55 to -30")
        }
        // Also migrate old WPM defaults
        let wpmMin = defaults.double(forKey: "targetWPMMin")
        if wpmMin > 0 && wpmMin < 135 {
            defaults.set(135.0, forKey: "targetWPMMin")
            defaults.set(185.0, forKey: "targetWPMMax")
            print("[ToneCoach] Migrated WPM defaults → 135-185")
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(for: Session.self)
    }
}

// MARK: - Main Tab Navigation
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PracticeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Practice", systemImage: "mic.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
        .tint(TCColor.accent)
        .preferredColorScheme(.dark)
    }
}
