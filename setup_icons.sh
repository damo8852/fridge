#!/bin/bash

echo "EcoPantry Icon Setup"
echo "===================="
echo
echo "Step 1: Make sure you have placed your EcoPantry logo as:"
echo "   assets/icon/ecopantry_logo.png (1024x1024px PNG)"
echo
echo "Step 2: Press Enter to generate all app icons..."
read
echo
echo "Generating icons..."
flutter pub run flutter_launcher_icons:main
echo
echo "Cleaning and rebuilding..."
flutter clean
flutter pub get
echo
echo "Icon setup complete! Your app now uses the EcoPantry logo."
echo "You can now run: flutter run"
echo
