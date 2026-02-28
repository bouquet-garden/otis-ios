# Otis Xcode Project

This directory contains the Otis iOS Swift source files.

## Files

- `AppleIntelligenceService.swift` - Apple Intelligence integration for AI-powered suggestions
- `SupabaseService.swift` - Supabase backend client for data persistence
- `OnboardingView.swift` - User onboarding flow UI
- `AISuggestionsViewModel.swift` - View model for AI-powered packing suggestions
- `WidgetDataManager.swift` - Widget data management and synchronization

## Architecture

These files follow the MVVM (Model-View-ViewModel) architecture pattern:

- **Services**: `AppleIntelligenceService`, `SupabaseService` - Business logic and API integration
- **Views**: `OnboardingView` - SwiftUI declarative UI components
- **ViewModels**: `AISuggestionsViewModel` - State management and data transformation
- **Managers**: `WidgetDataManager` - Cross-component data coordination

## Next Steps

To build a complete Xcode project:

1. Create a new iOS App project in Xcode 15+
2. Add these Swift files to the project
3. Configure Xcode project settings:
   - Bundle Identifier
   - Development Team
   - Code Signing
4. Add required dependencies:
   - Supabase Swift SDK
   - Any additional packages
5. Configure Info.plist for required permissions
6. Set up build schemes and configurations

The full Xcode project configuration (`.xcodeproj`) will be added in a future update.

## Development

Each file is production-ready and includes:

- Comprehensive error handling
- Async/await patterns for modern Swift concurrency
- Type-safe API interactions
- SwiftUI best practices
- Documentation comments