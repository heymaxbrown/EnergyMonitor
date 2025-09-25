# Tesla Energy Monitor

A macOS menu bar application that monitors your Tesla energy system in real-time.

## Features

- **Real-time Energy Monitoring**: Live data from your Tesla Powerwall, solar panels, and home energy usage
- **Menu Bar Integration**: Quick access to energy data without opening a separate app
- **Auto-refresh**: Automatically updates energy data every 30 seconds
- **Countdown Visualization**: Shows when the next data refresh will occur
- **Secure Authentication**: Uses Tesla's OAuth2 with Fleet API for secure access
- **Data Persistence**: Caches energy data for offline viewing
- **Dashboard View**: Detailed energy charts and historical data

## Requirements

- macOS 15.6 or later
- Tesla energy products (Powerwall, solar panels, etc.)
- Tesla Developer Account with Fleet API access

## Setup

1. **Tesla Developer Account**: Create an app at [developer.tesla.com](https://developer.tesla.com)
2. **Enable Fleet API**: Enable the Fleet API for your application
3. **Configure App**: Enter your Client ID and Client Secret in the app
4. **Authenticate**: Sign in with your Tesla account
5. **Monitor**: View your energy data in the menu bar

## Installation

1. Clone this repository
2. Open `EnergyMonitor.xcodeproj` in Xcode
3. Build and run the project
4. The app will appear in your menu bar

## Usage

- Click the lightning bolt icon in your menu bar to view energy data
- Use "Open Dashboard" to see detailed charts
- Click "Logout" to sign out of your Tesla account
- The app automatically refreshes data every 30 seconds

## Architecture

- **TeslaAuthService**: Handles OAuth2 authentication and API calls
- **MenuContentView**: Menu bar interface and data display
- **DashboardView**: Detailed energy charts and visualization
- **SecureTokenStore**: Secure storage of authentication tokens
- **PowerCache**: Energy data caching and persistence

## API Endpoints

- Tesla Fleet API for energy data
- OAuth2 authentication flow
- Real-time energy monitoring

## Version History

- **v1.0** (Current): Stable working version with auto-refresh and countdown
  - Tesla OAuth2 authentication working
  - Energy data fetching and display
  - Auto-refresh every 30 seconds
  - Countdown visualization
  - Menu bar integration
  - Dashboard window

## Development

This project uses SwiftUI and follows macOS app development best practices. The codebase is organized into logical modules for authentication, data management, and UI components.

## License

Private project for personal Tesla energy monitoring.