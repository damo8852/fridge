# EcoPantry Icon Setup

## Required File
Place your EcoPantry logo file here with the exact filename:
**`ecopantry_logo.png`**

## Requirements
- **Size**: 1024x1024 pixels
- **Format**: PNG with transparent background
- **Content**: Your EcoPantry logo (leaf with "ECO PANTRY" text)

## Steps to Complete Setup

1. **Save your EcoPantry logo** as `ecopantry_logo.png` in this directory
2. **Run the icon generation**:
   ```bash
   flutter pub get
   flutter pub run flutter_launcher_icons:main
   ```
3. **Clean and rebuild**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## What This Will Do
The flutter_launcher_icons package will automatically:
- Generate all required Android icon sizes (48px to 192px)
- Generate all required iOS icon sizes (20px to 1024px)
- Generate web icons (192px and 512px)
- Update all platform configuration files
- Apply the EcoPantry green theme colors

## Current Status
⏳ Waiting for `ecopantry_logo.png` file to be added to this directory
