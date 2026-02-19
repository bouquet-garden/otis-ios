// ContentView.swift
// Otis — Root tab navigation
//
// Three tabs: Trips | Passport | Settings
// iOS 26: Liquid Glass tab bar via native TabView rendering
// iOS 17–25: Standard tab bar with Otis teal tint

import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // MARK: - Tab State

    @State private var selectedTab: OtisTab = .trips

    // MARK: - Body

    var body: some View {
        if #available(iOS 26, *) {
            liquidGlassTabView
        } else {
            standardTabView
        }
    }

    // MARK: - iOS 26 Liquid Glass Tab Bar

    @available(iOS 26, *)
    private var liquidGlassTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Trips", systemImage: "house.fill", value: OtisTab.trips) {
                TripListView()
            }

            Tab("Passport", systemImage: "book.fill", value: OtisTab.passport) {
                PassportView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: OtisTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.otisTeal)
    }

    // MARK: - iOS 17–25 Standard Tab Bar

    private var standardTabView: some View {
        TabView(selection: $selectedTab) {
            TripListView()
                .tabItem {
                    Label("Trips", systemImage: "house.fill")
                }
                .tag(OtisTab.trips)

            PassportView()
                .tabItem {
                    Label("Passport", systemImage: "book.fill")
                }
                .tag(OtisTab.passport)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(OtisTab.settings)
        }
        .tint(.otisTeal)
        .onAppear {
            // Apply Otis teal tint to tab bar background on older iOS
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.otisCreame)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - OtisTab Enum

enum OtisTab: Hashable {
    case trips
    case passport
    case settings
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SubscriptionManager())
        .modelContainer(for: [Trip.self, PackingItem.self, PackingProfile.self, Stamp.self],
                        inMemory: true)
}
