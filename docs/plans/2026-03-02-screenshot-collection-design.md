# Screenshot Collection via XCUITest

## Problem
Collecting App Store screenshots through Claude API calls (one screenshot per round-trip) hits API rate limits and times out.

## Solution
XCUITest target that navigates the app and captures 10 screenshots in a single test run, independent of Claude.

## Screenshots (10)

| # | Screen | Navigation | Purpose |
|---|--------|------------|---------|
| 1 | Onboarding welcome | Launch with `--reset-onboarding` | Hook / first impression |
| 2 | Home screen | Complete onboarding → home | Hub overview |
| 3 | Opening browser | Home → "Browse Openings" | Catalog with difficulty |
| 4 | Opening detail (Italian) | Browser → Italian Game | Learning journey layers |
| 5 | Learning plan view | Detail → Layer 1 | Plan walkthrough + board |
| 6 | Training session | Detail → Layer 2 → play | Board + coaching feed |
| 7 | AI coaching panel | Session → chat icon | Coach chat + suggestions |
| 8 | Puzzle mode | Home → "Puzzles" | Puzzle solving |
| 9 | Trainer setup | Home → "Play Bot" | Bot personalities, Maia/Stockfish |
| 10 | Settings | Home → gear | Themes, AI coach config |

## Technical Design

### New target: `ChessCoachUITests`
- Added to `project.yml`
- Single test class: `ScreenshotCollectionTests`
- Each screenshot is a separate test method (can run individually)

### Launch arguments
- `--screenshot-mode`: Disables animations, pre-loads sample data
- `--reset-onboarding`: Shows onboarding flow from scratch
- App's `ContentView` checks for these flags and configures accordingly

### Screenshot capture
- `XCTAttachment` with `lifetime = .keepAlways`
- Named attachments for easy identification
- Extract from `.xcresult` bundle via `xcresulttool` or Xcode UI

### App-side changes
- Small launch argument handler in `ContentView` or `ChessCoachApp`
- Leverages existing `DebugStateView` infrastructure for state presets

## After Screenshots
Use captured screenshots for App Store Connect and TestFlight submission.
