# Add Missing Speech Phrases

This script adds specific speech phrases that are needed but may be missing from the catalog:

- **"Rest, 45 seconds"** - ID: `rest_basic_45`
- **"When you've completed 6 to 8 reps, press the arrow to move on"** - ID: `workout_rep_reminder_6_to_8`

This script focuses on adding only the two specific phrases requested.

## Usage

1. **Set your OpenAI API key:**
   ```bash
   export OPENAI_API_KEY=your_api_key_here
   ```

2. **Run the script:**
   ```bash
   cd scripts
   node add_missing_phrases.js
   ```

The script will:
- Generate MP3 audio files for the missing phrases
- Add them to `Chiron/SpeechAssets/`
- Update the `manifest.json` file with the new phrase mappings
- Skip any phrases that already exist

## What it does

1. Loads the existing manifest to check what's already there
2. Generates audio for:
   - `rest_basic_45` - "Rest, 45 Seconds"
   - `workout_rep_reminder_6_to_8` - "When you've completed 6 to 8 reps, press the arrow to move on"
3. Saves the audio files and updates the manifest

## Notes

- The script uses OpenAI TTS with the `nova` voice
- It includes rate limiting (100ms delay between requests)
- It will skip files that already exist
- Failed generations will be retried up to 3 times with exponential backoff
