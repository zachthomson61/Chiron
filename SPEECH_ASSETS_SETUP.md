# Speech Assets Setup Guide

This guide explains how to set up and use the pre-generated speech audio files.

## Generating Audio Files

1. **Install dependencies:**
   ```bash
   cd scripts
   npm install
   ```

2. **Set OpenAI API key:**
   ```bash
   export OPENAI_API_KEY=your_api_key_here
   ```

3. **Run the generation script:**
   ```bash
   npm run generate
   ```

   This will generate:
   - MP3 audio files in `Chiron/SpeechAssets/`
   - A `manifest.json` file mapping phrase IDs to filenames

## Adding Assets to Xcode Project

1. **Open the Xcode project**

2. **Add SpeechAssets folder to project:**
   - Right-click on the `Chiron` folder in the Project Navigator
   - Select "Add Files to Chiron..."
   - Navigate to `Chiron/SpeechAssets/`
   - Select the folder
   - Check "Create folder references" (NOT "Create groups")
   - Check "Add to targets: Chiron"
   - Click "Add"

3. **Verify files are in bundle:**
   - Select the project in Project Navigator
   - Select the "Chiron" target
   - Go to "Build Phases" tab
   - Expand "Copy Bundle Resources"
   - Verify that `SpeechAssets` folder (or individual MP3 files) are listed
   - If not, click "+" and add the `SpeechAssets` folder

4. **Alternative: Add files individually**
   If folder references don't work, you can add files individually:
   - Right-click on `Chiron` folder
   - Select "Add Files to Chiron..."
   - Navigate to `Chiron/SpeechAssets/`
   - Select all `.mp3` files and `manifest.json`
   - Check "Copy items if needed"
   - Check "Add to targets: Chiron"
   - Click "Add"

## How It Works

1. **Phrase Catalog** (`SpeechPhrases.swift`):
   - Contains all speech phrases with unique IDs
   - Organized by category (encouragement, feedback, instruction, etc.)
   - Includes both static phrases and dynamic phrase templates

2. **SpeechManager** (`SpeechManager.swift`):
   - Loads `manifest.json` from bundle on initialization
   - When `speak()` is called with text:
     - First tries to find exact phrase match in catalog
     - Then tries to construct phrase ID for dynamic phrases
     - Loads corresponding MP3 file from bundle
     - Falls back to system voice if file not found

3. **Build Script** (`scripts/generate_speech_assets.js`):
   - Reads phrase catalog
   - Calls OpenAI TTS API for each phrase
   - Generates MP3 files and manifest
   - Pre-generates common variations for dynamic phrases

## Dynamic Phrases

Some phrases include variables (e.g., "Rest, 30 Seconds", "You completed 5 reps"). The system:

1. **Pre-generates common variations:**
   - Rest durations: 10-300 seconds (in 10-second increments)
   - Rep counts: 1-20 reps
   - Analysis scores: 0-100 (in 5-point increments)

2. **Rounds/clamps values at runtime:**
   - Rest durations rounded to nearest 10 seconds
   - Rep counts clamped to 1-20 range
   - Scores rounded to nearest 5 points

3. **Falls back to system voice:**
   - If a variation isn't pre-generated, uses system TTS
   - This ensures all phrases work, even if not pre-generated

## Testing

After adding assets to the project:

1. Build and run the app
2. Trigger speech in various scenarios:
   - Start a workout (exercise setup cues)
   - Complete reps (encouragement phrases)
   - Rest periods (rest announcements)
   - Analysis results (score announcements)
3. Verify audio plays correctly
4. Check console logs for any "Phrase not found" warnings

## Troubleshooting

**Audio files not playing:**
- Verify `SpeechAssets` folder is in "Copy Bundle Resources"
- Check that `manifest.json` exists in the bundle
- Look for console errors about missing files

**Phrases falling back to system voice:**
- Check that phrase text matches exactly (case-sensitive)
- Verify the phrase ID is in `manifest.json`
- Check that corresponding MP3 file exists

**Build script errors:**
- Verify OpenAI API key is set correctly
- Check API rate limits (script includes delays)
- Review error messages for specific failures
