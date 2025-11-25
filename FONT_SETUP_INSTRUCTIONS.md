# Neue Montreal Font Setup Instructions

## Overview
The app has been configured to use Neue Montreal font throughout. The font infrastructure is in place, but you need to add the actual font files to complete the setup.

**Note:** The app will automatically fall back to system fonts if the custom fonts are not available, so it will work even before font files are added.

## Font Files Required
You need three font files (either `.otf` or `.ttf` format):
- `NeueMontreal-Regular.otf` (or `.ttf`)
- `NeueMontreal-SemiBold.otf` (or `.ttf`)
- `NeueMontreal-Bold.otf` (or `.ttf`)

## Steps to Add Font Files

1. **Obtain the font files** from your font provider or design team

2. **Add fonts to Xcode project:**
   - Drag and drop the font files into the `Chiron` folder in Xcode
   - Make sure "Copy items if needed" is checked
   - Ensure the fonts are added to the "Chiron" target

3. **Verify Info.plist:**
   - The `UIAppFonts` array has been added to `Info.plist` (lines 48-56)
   - It includes entries for both `.otf` and `.ttf` extensions to handle either format
   - The font names should match exactly what's in the font files

4. **Check font names:**
   - The font extension (`Font+Extensions.swift`) automatically tries multiple naming conventions:
     - `NeueMontreal-Regular`, `NeueMontreal-SemiBold`, `NeueMontreal-Bold`
     - `Neue Montreal Regular`, `Neue Montreal SemiBold`, `Neue Montreal Bold`
   - If your font files use different names, update the font extension accordingly

5. **Test the fonts:**
   - Build and run the app
   - If fonts don't appear, check the console for font loading errors
   - The app will fall back to system fonts if custom fonts aren't found

## Font Usage Throughout App

The app uses three font weights consistently:
- **Bold** (`neueMontrealBold(size:)`): Used for headers, titles, and emphasis
- **SemiBold** (`neueMontrealSemiBold(size:)`): Used for buttons and important interactive elements
- **Regular** (`neueMontrealRegular(size:)`): Used for body text, captions, and general content

## Implementation Details

- **Font Extension**: `Chiron/Extensions/Font+Extensions.swift`
  - Provides three static methods for each font weight
  - Automatically falls back to system fonts if custom fonts aren't available
  - Handles multiple font naming conventions

- **Info.plist Configuration**: `Chiron/Info.plist`
  - `UIAppFonts` array (lines 48-56) registers font files with the system
  - Includes both `.otf` and `.ttf` entries to support either format

- **All Views Updated**: All view files throughout the app have been updated to use the new font helpers instead of system fonts

