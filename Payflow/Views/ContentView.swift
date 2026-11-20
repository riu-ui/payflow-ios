import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var auth: BiometricAuthService
    @AppStorage("payflow.hasOnboarded") private var hasOnboarded = false
    @AppStorage("payflow.requireBiometrics") private var requireBiometrics = true
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if requireBiometrics && !auth.isUnlocked {
                LockScreenView()
            } else {
                MainTabView()
            }
        }
        .payScreenBackground()
        .onAppear {
            if !hasOnboarded { showOnboarding = true }
            if !requireBiometrics { auth.isUnlocked = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasOnboarded = true
                showOnboarding = false
            }
        }
        .task {
            if requireBiometrics && !auth.isUnlocked {
                _ = await auth.authenticate()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.fill") }
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "wallet.pass") }
            SubscriptionsView()
                .tabItem { Label("Subscriptions", systemImage: "repeat") }
            AIAssistantView()
                .tabItem { Label("Assistant", systemImage: "sparkles") }
            IntegrationsView()
                .tabItem { Label("Integrations", systemImage: "link") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(PayTheme.emerald)
        .toolbarBackground(PayTheme.surfaceElevated, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct LockScreenView: View {
    @EnvironmentObject private var auth: BiometricAuthService
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(PayTheme.emerald)
            Text("PAYFLOW")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(PayTheme.textPrimary)
            Text("Your finances are locked.\nAuthenticate with \(auth.biometryType) to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(PayTheme.textSecondary)
            Button {
                Task { _ = await auth.authenticate() }
            } label: {
                Label("Unlock with \(auth.biometryType)", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(PayTheme.emerald)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            if let err = auth.lastError {
                Text(err).font(.caption).foregroundStyle(PayTheme.danger).padding(.horizontal)
            }
            Spacer()
            Text("Local-first · No banking passwords stored · Face ID only")
                .font(.caption)
                .foregroundStyle(PayTheme.textMuted)
        }
        .payScreenBackground()
    }
}

struct OnboardingView: View {
    var done: () -> Void
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome to PAYFLOW")
                    .font(.largeTitle.bold())
                    .foregroundStyle(PayTheme.textPrimary)
                Text("Private, local-first finance. No account, no cloud by default, no banking passwords.")
                    .foregroundStyle(PayTheme.textSecondary)
                ForEach([
                    ("tray.and.arrow.down.fill", "Import a statement", "CSV, XLSX or PDF — categorised and deduplicated automatically."),
                    ("faceid", "Protected by Face ID", "The app locks whenever it leaves the screen."),
                    ("sparkles", "Local AI first", "Insights are computed on your iPhone. External AI is off unless you explicitly turn it on."),
                    ("building.columns", "Banks, honestly", "Bank connections use your bank's official sign-in. PAYFLOW never asks for, or stores, a banking password, PIN or OTP."),
                    ("bolt.fill", "Automatic notifications", "Pay with Apple Pay and PAYFLOW can log it and notify you — set up once in Shortcuts, under Integrations → Automation. It only receives payments you route to it."),
                ], id: \.1) { icon, title, body in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: icon).foregroundStyle(PayTheme.emerald).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).bold().foregroundStyle(PayTheme.textPrimary)
                            Text(body).font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        }
                    }
                }
                Spacer()
                Button("Get started", action: done)
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(PayTheme.emerald).foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
            .payScreenBackground()
        }
    }
}
