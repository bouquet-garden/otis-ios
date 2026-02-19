# Otis 🦦

> *Otis helps you pack smarter, worry less, and collect the stamps to prove it.*

A beautiful, calm iOS packing app anchored by a pixel otter mascot named **Otis**. The core loop: build a packing list for your trip, get AI-powered suggestions, complete the list, earn a passport stamp. Repeat across trips. Otis grows as your travel history does.

## What It Is

- Trip packing list builder with AI-powered suggestions (OpenAI GPT-4o-mini)
- Passport stamp collection — one stamp per completed trip
- Otis the otter mascot — calm by default, expressive during celebrations
- Free tier + Pro ($19.99/yr or $59.99 lifetime via RevenueCat)
- iOS only, SwiftUI + MVVM + CloudKit sync

## Tech Stack

- SwiftUI (iOS 17+)
- MVVM architecture
- CloudKit (iCloud sync, Pro feature)
- OpenAI API (GPT-4o-mini for packing suggestions)
- RevenueCat (subscriptions)
- SwiftData (local persistence)

## Project Structure

```
otis-ios/
├── Models/          # Swift structs + SwiftData models
├── Views/           # SwiftUI views by feature
│   ├── TripCreation/
│   ├── PackingList/
│   ├── AISuggestions/
│   ├── Passport/
│   ├── Paywall/
│   └── Widgets/
├── ViewModels/      # Observable ViewModels per feature
├── Services/        # OpenAI, RevenueCat, StampService, CloudKit
└── Assets/          # Otis pixel art, stamp designs, app icon
```

## Status

🚧 Active development

## Monetization

| Plan | Price |
|------|-------|
| Free | $0 forever — full list builder, last 3 trips |
| Pro Annual | $19.99/year |
| Lifetime | $59.99 one-time (launch offer) |

**Rule: Never gate the beauty. Only gate the intelligence.**