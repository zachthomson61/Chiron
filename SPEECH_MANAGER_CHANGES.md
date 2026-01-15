# SpeechManager Changes Summary

## Overview
This document describes the changes made to `SpeechManager.swift` to fix phrase ID matching issues and improve audio session management for video playback compatibility.

## Changes Made

### 1. Fixed Phrase ID Matching Order (`constructPhraseId` method)

**Problem:** 
- "Rest, 45 Seconds" was being incorrectly matched as `workout_exercise_rest_45_seconds` instead of `rest_basic_45`
- "When you've completed 6 to 8 reps, press the arrow to move on" was being incorrectly matched as an exercise phrase instead of `workout_rep_reminder_6_to_8`

**Solution:** 
Reordered the pattern checks in `constructPhraseId()` to match more specific patterns before generic ones:

1. "First up" exercise phrases
2. "Next up" exercise phrases
3. **Rest announcements** (moved before generic exercise check)
4. **Rep reminders** (moved before generic exercise check)
5. Generic exercise guide phrases
6. Time reminders
7. Analysis phrases

**Files Changed:**
- `Chiron/SpeechManager.swift` - Lines ~342-420 in `constructPhraseId()` method

### 2. Improved Audio Session Management (`setupAudioSession` method)

**Problem:** 
- Audio session deactivation was interrupting video playback, causing `-12860` PlayerRemoteXPC errors
- Video would disappear when speech audio started playing

**Solution:** 
- Removed the `setActive(false)` call that was interrupting video playback
- Changed to only update audio session category when needed, without deactivating first
- Audio session now activates without deactivating, preserving video playback with `.mixWithOthers` option

**Files Changed:**
- `Chiron/SpeechManager.swift` - Lines ~683-714 in `setupAudioSession()` method

### 3. Improved Ducking Management (`setDuckingEnabled` method)

**Problem:** 
- Audio session category was being changed unnecessarily on every ducking toggle, potentially interrupting video

**Solution:** 
- Added check to only change category if ducking state actually needs to change
- Prevents unnecessary audio session modifications that could interrupt video playback

**Files Changed:**
- `Chiron/SpeechManager.swift` - Lines ~738-753 in `setDuckingEnabled()` method

### 4. Adjusted Audio File Load Timeout (`playPhrase` method)

**Problem:** 
- 100ms timeout was too aggressive, causing premature fallback to OpenAI TTS
- Network errors were appearing in logs even when local files were available

**Solution:** 
- Increased timeout from 100ms to 500ms to allow more time for file loading
- Changed fallback to use system voice instead of OpenAI TTS to avoid network errors when offline
- System voice fallback is more reliable and doesn't require network connectivity

**Files Changed:**
- `Chiron/SpeechManager.swift` - Lines ~585-638 in `playPhrase()` method

### 5. Removed Beep Tone from Rep Reminders (`WorkoutIntroView.swift`)

**Problem:** 
- Beep tone was playing when rep range reminders fired, interrupting user's workout pace

**Solution:** 
- Removed `playBeepTone()` and `triggerEndHaptic()` calls from rep reminder timer callback
- Users can now move at their own pace when rep range suggestions are provided

**Files Changed:**
- `Chiron/Views/WorkoutIntroView.swift` - Lines ~1653-1664 in `startExercise()` method

## Technical Details

### Audio Session Configuration
The audio session is configured with:
- **Category:** `.playback`
- **Mode:** `.default`
- **Options:** `.mixWithOthers` (and `.duckOthers` when ducking is enabled)

This configuration allows:
- Speech audio to play alongside video playback
- Background music (e.g., Spotify) to continue playing
- Video playback to remain uninterrupted when speech starts

### Phrase ID Matching Priority
The order of pattern matching ensures:
- Specific patterns (rest announcements, rep reminders) are matched before generic patterns
- Exercise phrases are only matched when no more specific pattern applies
- Prevents false matches that would cause incorrect audio file lookups

## Testing Notes

After these changes:
- ✅ Rest announcements correctly match `rest_basic_X` phrases
- ✅ Rep reminders correctly match `workout_rep_reminder_X` or `workout_rep_reminder_X_to_Y` phrases
- ✅ Video playback continues uninterrupted when speech plays
- ✅ No beep tones during rep range reminders
- ✅ Fewer network errors in logs (system voice used for fallbacks instead of OpenAI TTS)

## Related Files

- `Chiron/SpeechManager.swift` - Main changes
- `Chiron/Views/WorkoutIntroView.swift` - Removed beep tone
- `Chiron/AudioSessionManager.swift` - App-wide audio session configuration (unchanged, but works with these changes)
