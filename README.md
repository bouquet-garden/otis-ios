# Otis iOS

AI-powered travel companion app for iOS built with SwiftUI.

## Overview

Otis helps travelers organize their trips with intelligent packing lists, AI-powered suggestions, and beautiful passport stamp collections.

## Features

- Smart packing list generation
- AI-powered travel suggestions using Apple Intelligence
- Trip organization and management
- Passport stamp collection
- Widget support for quick access
- Supabase backend integration

## Architecture

- **SwiftUI** for modern declarative UI
- **MVVM** architecture pattern
- **Supabase** for backend services
- **Apple Intelligence** for AI features
- **WidgetKit** for home screen widgets

## Project Structure

```
Otis/
├── AppleIntelligenceService.swift  # AI integration layer
├── SupabaseService.swift            # Backend service layer
├── OnboardingView.swift             # User onboarding flow
├── AISuggestionsViewModel.swift     # AI suggestions logic
└── WidgetDataManager.swift          # Widget data management
```

## Setup

1. Open `Otis.xcodeproj` in Xcode
2. Configure Supabase credentials
3. Build and run on iOS simulator or device

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

---

Built with love by Bouquet Garden