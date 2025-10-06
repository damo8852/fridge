# EcoPantry App Icon Setup Guide

## Overview
This guide will help you set up the EcoPantry app icon across all platforms (Android, iOS, Web).

## Icon Requirements

### Android Icons
You need to create the following icon sizes and place them in the respective directories:

**Directory: `android/app/src/main/res/mipmap-*/`**
- `mipmap-mdpi/ic_launcher.png` - 48x48px
- `mipmap-hdpi/ic_launcher.png` - 72x72px  
- `mipmap-xhdpi/ic_launcher.png` - 96x96px
- `mipmap-xxhdpi/ic_launcher.png` - 144x144px
- `mipmap-xxxhdpi/ic_launcher.png` - 192x192px

### iOS Icons
You need to create the following icon sizes and place them in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`:

- `Icon-App-20x20@1x.png` - 20x20px
- `Icon-App-20x20@2x.png` - 40x40px
- `Icon-App-20x20@3x.png` - 60x60px
- `Icon-App-29x29@1x.png` - 29x29px
- `Icon-App-29x29@2x.png` - 58x58px
- `Icon-App-29x29@3x.png` - 87x87px
- `Icon-App-40x40@1x.png` - 40x40px
- `Icon-App-40x40@2x.png` - 80x80px
- `Icon-App-40x40@3x.png` - 120x120px
- `Icon-App-60x60@2x.png` - 120x120px
- `Icon-App-60x60@3x.png` - 180x180px
- `Icon-App-76x76@1x.png` - 76x76px
- `Icon-App-76x76@2x.png` - 152x152px
- `Icon-App-83.5x83.5@2x.png` - 167x167px
- `Icon-App-1024x1024@1x.png` - 1024x1024px (App Store)

### Web Icons
You need to create the following icon sizes and place them in `web/icons/`:

- `Icon-192.png` - 192x192px
- `Icon-512.png` - 512x512px
- `Icon-maskable-192.png` - 192x192px (maskable)
- `Icon-maskable-512.png` - 512x512px (maskable)

## EcoPantry Logo Design
Based on the provided logo description:
- **Background**: Dark green (#27AE60 or similar)
- **Icon**: White leaf shape with "ECO" and "PANTRY" text
- **Style**: Clean, modern, sustainable theme

## Recommended Tools
1. **Figma** - For creating the icon design
2. **Icon Kitchen** (https://icon.kitchen/) - For generating all required sizes
3. **App Icon Generator** - Online tools for Flutter app icons

## Steps to Create Icons

### Step 1: Create Base Icon
1. Create a 1024x1024px base icon with the EcoPantry logo
2. Ensure it has a transparent background or solid background
3. Make sure the design is clear at small sizes

### Step 2: Generate All Sizes
1. Use Icon Kitchen or similar tool to generate all required sizes
2. Download the generated icons

### Step 3: Replace Existing Icons
1. Replace all the existing icon files in the directories listed above
2. Keep the same filenames
3. Ensure all files are properly formatted (PNG)

### Step 4: Test the Icons
1. Run `flutter clean`
2. Run `flutter pub get`
3. Build and test on different platforms:
   - `flutter run` for mobile
   - `flutter run -d chrome` for web

## Alternative: Using flutter_launcher_icons Package

You can also use the `flutter_launcher_icons` package to automatically generate icons:

1. Add to `pubspec.yaml`:
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/icon/icon.png"
  web:
    generate: true
    image_path: "assets/icon/icon.png"
    background_color: "#27AE60"
    theme_color: "#27AE60"
```

2. Create your icon at `assets/icon/icon.png` (1024x1024px)
3. Run `flutter pub get`
4. Run `flutter pub run flutter_launcher_icons:main`

## Notes
- Make sure the icon design is recognizable at small sizes
- The iOS icons will be automatically rounded by the system
- Web icons should have proper contrast for different backgrounds
- Test the icons on actual devices to ensure they look good

## Current Status
✅ App name updated to "EcoPantry" across all platforms
✅ Theme colors updated to green (#27AE60)
✅ Configuration files updated
✅ flutter_launcher_icons package installed and configured
⏳ Waiting for EcoPantry logo file to be added

## Quick Setup (Automated)
1. **Add your logo**: Save your EcoPantry logo as `assets/icon/ecopantry_logo.png` (1024x1024px)
2. **Run the setup script**:
   - Windows: Double-click `setup_icons.bat`
   - Mac/Linux: Run `./setup_icons.sh`
3. **Or run manually**:
   ```bash
   flutter pub run flutter_launcher_icons:main
   flutter clean
   flutter pub get
   flutter run
   ```

After adding your logo file and running the setup, the app will be fully branded as EcoPantry!
