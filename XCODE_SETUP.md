# Xcode Project Setup Guide

Since Xcode project files (.xcodeproj) are complex binary formats, follow these steps to create the project:

## Step 1: Create New Xcode Project

1. Open Xcode
2. File -> New -> Project (or Cmd+Shift+N)
3. Select **iOS** -> **App**
4. Click **Next**
5. Configure:
   - Product Name: `CaboGame`
   - Team: Your team (or None)
   - Organization Identifier: `com.yourname` (or any identifier)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck "Include Tests" (optional)
6. Click **Next**
7. Save to: `/Users/george/Desktop/cabo-xcode/` (temporary location)

## Step 2: Replace Generated Files

1. In Finder, navigate to the newly created project folder
2. Delete the auto-generated `CaboGameApp.swift` and `ContentView.swift`
3. Copy all folders from `/Users/george/Desktop/cabo/CaboGame/` into the Xcode project folder:
   - Models/
   - Engine/
   - Networking/
   - ViewModels/
   - Views/
   - Utils/
   - CaboGameApp.swift
   - Assets.xcassets/ (replace existing)
   - Info.plist (replace existing)

## Step 3: Add Files to Xcode

1. In Xcode, right-click on the `CaboGame` folder in the navigator
2. Select "Add Files to CaboGame..."
3. Select all the folders you copied (Models, Engine, etc.)
4. Make sure "Copy items if needed" is **unchecked**
5. Make sure "Create groups" is selected
6. Click **Add**

## Step 4: Configure Build Settings

1. Select the project in the navigator (blue icon)
2. Select the `CaboGame` target
3. Go to **General** tab:
   - Deployment Target: iOS 16.0 or later
   - Device Orientation: Portrait only (uncheck Landscape)
4. Go to **Info** tab:
   - Verify App Transport Security settings allow local connections

## Step 5: Build and Run

1. Select an iPhone simulator (iPhone 15 Pro recommended)
2. Press Cmd+R to build and run
3. The app should launch to the lobby screen

## Troubleshooting

### "No such module" errors
Make sure all files are properly added to the target. Select each file and verify the target membership checkbox is checked.

### Network issues
The app needs the server running. In Terminal:
```bash
cd /Users/george/Desktop/cabo/Server
npm install
npm start
```

### UIDevice errors
If you see UIDevice errors, add `import UIKit` at the top of Player.swift.

