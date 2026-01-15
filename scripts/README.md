# Speech Assets Generation

This directory contains the build script to generate speech audio assets using OpenAI TTS.

## Setup

1. Install Node.js dependencies:
   ```bash
   cd scripts
   npm install
   ```

2. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY=your_api_key_here
   ```

## Usage

Run the generation script:
```bash
npm run generate
```

Or directly:
```bash
node generate_speech_assets.js
```

The script will:
- Generate MP3 audio files for all phrases in the catalog
- Save them to `Chiron/SpeechAssets/`
- Create a `manifest.json` mapping phrase IDs to filenames
- Skip files that already exist (useful for resuming interrupted runs)

## Output

- **Audio files**: `Chiron/SpeechAssets/*.mp3` - One MP3 file per phrase
- **Manifest**: `Chiron/SpeechAssets/manifest.json` - Maps phrase IDs to filenames

## Notes

- The script includes rate limiting to respect OpenAI API limits
- Failed requests are retried with exponential backoff
- Progress is shown every 10 phrases
- Total generation time depends on the number of phrases (~500+ phrases)

## Adding New Phrases

1. Add the phrase to `Chiron/SpeechPhrases.swift`
2. Re-run the generation script
3. The new phrase will be generated automatically
