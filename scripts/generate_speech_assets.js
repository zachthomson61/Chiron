#!/usr/bin/env node

/**
 * Generate speech audio assets using OpenAI TTS API
 * 
 * This script:
 * 1. Reads the phrase catalog from SpeechPhrases.swift (or a JSON export)
 * 2. Calls OpenAI TTS API for each phrase
 * 3. Saves MP3 files to Chiron/SpeechAssets/
 * 4. Generates a manifest.json mapping phrase IDs to filenames
 * 
 * Usage:
 *   OPENAI_API_KEY=your_key node generate_speech_assets.js
 * 
 * Or set the API key in your environment:
 *   export OPENAI_API_KEY=your_key
 *   node generate_speech_assets.js
 */

import { OpenAI } from 'openai';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Get API key from environment
const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
    console.error('❌ Error: OPENAI_API_KEY environment variable is required');
    console.error('   Set it with: export OPENAI_API_KEY=your_key');
    process.exit(1);
}

// Initialize OpenAI client
const openai = new OpenAI({ apiKey });

// Paths
const projectRoot = path.resolve(__dirname, '..');
const assetsDir = path.join(projectRoot, 'Chiron', 'SpeechAssets');
const manifestPath = path.join(assetsDir, 'manifest.json');

// Ensure assets directory exists
if (!fs.existsSync(assetsDir)) {
    fs.mkdirSync(assetsDir, { recursive: true });
    console.log(`📁 Created directory: ${assetsDir}`);
}

// Rate limiting: OpenAI TTS has rate limits, so we'll add delays
const DELAY_BETWEEN_REQUESTS = 100; // milliseconds

/**
 * Generate audio for a single phrase
 */
async function generateAudio(phraseId, text, retries = 3) {
    const outputPath = path.join(assetsDir, `${phraseId}.mp3`);
    
    // Skip if file already exists
    if (fs.existsSync(outputPath)) {
        console.log(`⏭️  Skipping ${phraseId} (already exists)`);
        return { success: true, phraseId, skipped: true };
    }
    
    for (let attempt = 1; attempt <= retries; attempt++) {
        try {
            console.log(`🎤 Generating audio for: ${phraseId} (attempt ${attempt}/${retries})`);
            
            const response = await openai.audio.speech.create({
                model: 'tts-1',
                voice: 'nova',
                input: text,
                response_format: 'mp3'
            });
            
            // Save the audio file
            const buffer = Buffer.from(await response.arrayBuffer());
            fs.writeFileSync(outputPath, buffer);
            
            console.log(`✅ Generated: ${phraseId}.mp3 (${(buffer.length / 1024).toFixed(1)} KB)`);
            return { success: true, phraseId, size: buffer.length };
            
        } catch (error) {
            console.error(`❌ Error generating ${phraseId} (attempt ${attempt}/${retries}):`, error.message);
            
            if (attempt < retries) {
                // Exponential backoff
                const delay = Math.pow(2, attempt) * 1000;
                console.log(`   Retrying in ${delay}ms...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            } else {
                return { success: false, phraseId, error: error.message };
            }
        }
    }
    
    return { success: false, phraseId, error: 'Max retries exceeded' };
}

/**
 * Load phrases from the catalog.
 *
 * Source of truth is Chiron/SpeechPhrases.swift. Static phrases are parsed
 * directly from that file (regex over the `SpeechPhrase(id:...,text:...)`
 * entries). Templates containing `{placeholder}` are skipped here — their
 * filled-in variations come from `generateDynamicVariations()` below.
 *
 * The dynamic generation logic mirrors `SpeechPhraseCatalog.generateDynamicVariations()`
 * in Swift; any changes there must be mirrored here. (The hardcoded `exercises`
 * and `repTimeFormats` lists also mirror Swift's `generateExercisePhrases()`.)
 */
function loadPhrases() {
    const swiftPath = path.join(projectRoot, 'Chiron', 'SpeechPhrases.swift');
    const src = fs.readFileSync(swiftPath, 'utf8');

    // Match each `SpeechPhrase(id: "...", text: "...", category: ...)` entry.
    // The text capture handles backslash-escaped characters inside the string.
    const entryRe = /SpeechPhrase\(\s*id:\s*"([^"]+)"\s*,\s*text:\s*"((?:[^"\\]|\\.)*)"\s*,\s*category:/g;
    const staticPhrases = [];
    let m;
    while ((m = entryRe.exec(src)) !== null) {
        const id = m[1];
        const text = m[2]
            .replace(/\\"/g, '"')
            .replace(/\\\\/g, '\\');
        // Skip placeholder templates (e.g. "Rest, {duration} Seconds") —
        // these are enumerated below with concrete values.
        if (/\{[a-zA-Z]+\}/.test(text)) continue;
        staticPhrases.push({ id, text });
    }

    return [...staticPhrases, ...generateDynamicVariations()];
}

function sanitizeForId(text) {
    return text.toLowerCase()
        .replace(/\s+/g, '_')
        .replace(/-/g, '_')
        .replace(/,/g, '')
        .replace(/\./g, '')
        .replace(/\(/g, '')
        .replace(/\)/g, '');
}

/**
 * Mirror of `SpeechPhraseCatalog.generateDynamicVariations()` in Swift.
 * Keep ranges/increments in sync with that function.
 */
function generateDynamicVariations() {
    const variations = [];

    // Exercise-specific phrases (mirrors Swift's generateExercisePhrases()).
    // Keep this list aligned with the `exercises` array in SpeechPhrases.swift.
    const exercises = [
        { name: 'Cross-Body Arm Swings', side: null },
        { name: 'Cross-Body Arm Swings', side: 'Right Side' },
        { name: 'Cross-Body Arm Swings', side: 'Left Side' },
        { name: 'Arm Circles', side: null },
        { name: 'Thread the Needle', side: 'Right Side' },
        { name: 'Thread the Needle', side: 'Left Side' },
        { name: 'Overhead Tricep Stretch', side: 'Right Side' },
        { name: 'Overhead Tricep Stretch', side: 'Left Side' },
        { name: 'Standing Wall Bicep Stretch', side: 'Right Side' },
        { name: 'Standing Wall Bicep Stretch', side: 'Left Side' },
        { name: 'Close-Grip Bench Press', side: null },
        { name: 'Alternating DB Curls', side: null },
        { name: 'Incline DB Curl', side: null },
        { name: 'Rope Tricep Pushdown', side: null },
        { name: 'EZ-Bar Drag Curl', side: null },
        { name: 'Overhead Rope Extension', side: null },
        { name: 'Barbell Bicep Curl', side: null },
        { name: 'Bench Dip', side: null },
        { name: 'Hammer Curl Hold', side: null },
        { name: 'Cross-body Tricep Stretch', side: 'Right Side' },
        { name: 'Cross-body Tricep Stretch', side: 'Left Side' },
    ];

    const repTimeFormats = [
        '30 seconds',
        '45 seconds',
        '90 seconds',
        '21 seconds',
        '6-8 reps',
        '10-12 reps',
        '6 to 8 reps',
        '10 to 12 reps',
    ];

    for (const ex of exercises) {
        const fullName = ex.side ? `${ex.name} - ${ex.side}` : ex.name;
        const idStem = sanitizeForId(fullName);
        for (const repTime of repTimeFormats) {
            const idRep = sanitizeForId(repTime);
            variations.push({ id: `workout_first_up_${idStem}_${idRep}`, text: `First up, ${fullName}, ${repTime}` });
            variations.push({ id: `workout_next_up_${idStem}_${idRep}`, text: `Next up, ${fullName}, ${repTime}` });
            variations.push({ id: `workout_exercise_${idStem}_${idRep}`, text: `${fullName}, ${repTime}` });
        }
    }

    // Rest announcements: 5-300 seconds in 5-second increments (matches Swift).
    for (let duration = 5; duration <= 300; duration += 5) {
        variations.push({ id: `rest_basic_${duration}`, text: `Rest, ${duration} Seconds` });
        variations.push({ id: `rest_you_deserve_it_${duration}`, text: `Rest, ${duration} Seconds. You deserve it!` });
        variations.push({ id: `rest_stretch_${duration}`, text: `Rest, ${duration} Seconds. Stretch out a bit.` });
        variations.push({ id: `rest_drink_water_${duration}`, text: `Rest, ${duration} Seconds. Take a drink of water if you're thirsty.` });
        variations.push({ id: `rest_recover_next_set_${duration}`, text: `Rest, ${duration} Seconds. Recover and then let's get this next set!` });
    }

    // Rep reminders: 1-20 reps
    for (let count = 1; count <= 20; count++) {
        variations.push({ id: `workout_rep_reminder_${count}`, text: `When you've completed ${count} reps, press the arrow to move on` });
    }

    // Analysis score variations: 0-100 in increments of 5
    for (let score = 0; score <= 100; score += 5) {
        variations.push({ id: `analysis_excellent_work_${score}`, text: `Excellent work! You scored ${score} percent. ` });
        variations.push({ id: `analysis_good_job_${score}`, text: `Good job! Your form score was ${score} percent. ` });
        variations.push({ id: `analysis_work_on_improving_${score}`, text: `Your form score was ${score} percent - let's work on improving that. ` });
    }

    // Analysis rep count variations: 1-20 reps
    for (let count = 1; count <= 20; count++) {
        variations.push({ id: `analysis_completed_solid_reps_${count}`, text: `You completed ${count} solid reps. ` });
        variations.push({ id: `analysis_nice_work_reps_${count}`, text: `Nice work on those ${count} reps. ` });
    }

    // Set start: 1-20
    for (let setNumber = 1; setNumber <= 20; setNumber++) {
        variations.push({ id: `workout_starting_set_${setNumber}`, text: `Starting set ${setNumber}` });
    }

    // PR celebration (bodyweight): 1-50 reps
    for (let reps = 1; reps <= 50; reps++) {
        variations.push({ id: `pr_celebration_bodyweight_${reps}`, text: `Personal record — ${reps} reps. Huge work.` });
    }

    // Deterministic LLM-fail fallback combinations. Mirrors the
    // `fallbackBestThings` × `fallbackCues` enumeration in
    // SpeechPhrases.swift. Keep both lists aligned — every entry here must
    // have a matching entry in the Swift catalog or the matcher in
    // SpeechManager.constructFallbackPhraseId will miss at runtime.
    const fallbackBestThings = [
        { text: 'Nice effort there', key: 'nice_effort' },
        { text: 'Good depth on that set', key: 'good_depth' },
        { text: 'Chest stayed nice and tall', key: 'chest_tall' },
        { text: 'Knees tracked well over your toes', key: 'knees_over_toes' },
        { text: 'Solid lockout at the top', key: 'solid_lockout_top' },
        { text: 'Tempo stayed controlled', key: 'tempo_controlled' },
        { text: 'Back stayed nice and flat', key: 'back_flat' },
        { text: 'Solid hip position throughout', key: 'solid_hip_position' },
        { text: 'Elbows stayed tight to your sides', key: 'elbows_tight' },
        { text: 'Really clean rows', key: 'clean_rows' },
        { text: 'Back stayed flat the whole way up', key: 'back_flat_pull' },
        { text: 'Hips and shoulders moved together nicely', key: 'hips_shoulders_together' },
        { text: 'Strong lockout position', key: 'strong_lockout' },
        { text: 'Bar stayed tight to your body', key: 'bar_tight_body' },
        { text: 'Really clean pulls', key: 'clean_pulls' },
        { text: 'Smooth hip hinge with a flat back', key: 'smooth_hinge' },
        { text: 'Knees stayed nice and soft without bending', key: 'soft_knees' },
        { text: 'Good depth on that hinge', key: 'good_depth_hinge' },
        { text: 'Bar stayed right against your legs', key: 'bar_against_legs' },
        { text: 'Textbook Romanian deadlifts', key: 'textbook_rdl' },
        { text: 'Controlled tempo', key: 'controlled_tempo' },
    ];
    const fallbackCues = [
        { lowercasedText: 'sit deeper until hips reach knee level', issueCode: 'insufficient_depth' },
        { lowercasedText: 'keep your chest tall and proud', issueCode: 'forward_lean' },
        { lowercasedText: 'push your knees out over your toes', issueCode: 'knee_valgus' },
        { lowercasedText: 'keep your knees tracking straight ahead', issueCode: 'knee_varus' },
        { lowercasedText: 'bring your grip in closer to your ribs', issueCode: 'grip_too_wide' },
        { lowercasedText: 'tuck those elbows to your sides', issueCode: 'elbows_flaring' },
        { lowercasedText: 'lock out fully at the top and touch your chest at the bottom', issueCode: 'incomplete_rom' },
        { lowercasedText: 'take more time lowering the bar', issueCode: 'eccentric_too_fast' },
        { lowercasedText: 'press up a little faster', issueCode: 'concentric_too_slow' },
        { lowercasedText: 'hold the stretch at the bottom for a full second', issueCode: 'insufficient_stretch_pause' },
        { lowercasedText: "keep your back flat and close to parallel with the ground — don't stand up between reps", issueCode: 'row_momentum_drive' },
        { lowercasedText: "brace your core and keep your spine flat — don't let your back round", issueCode: 'row_rounded_back' },
        { lowercasedText: 'point your toes and knees straight ahead', issueCode: 'row_knee_internal_rotation' },
        { lowercasedText: 'pull your elbows back toward your hips, not out to the sides', issueCode: 'row_elbow_flare' },
        { lowercasedText: 'brace hard and lock in a flat back from setup to lockout', issueCode: 'deadlift_rounded_back' },
        { lowercasedText: 'push through your legs first so hips and shoulders rise together', issueCode: 'deadlift_hip_shoot_up' },
        { lowercasedText: 'stand tall at the top without leaning back', issueCode: 'deadlift_hyperextension' },
        { lowercasedText: 'keep the bar tight to your body the whole way up', issueCode: 'deadlift_bar_drift' },
        { lowercasedText: 'brace your core and keep your spine flat all the way down', issueCode: 'rdl_rounded_back' },
        { lowercasedText: 'keep your knees at a soft fixed bend — push your hips back instead', issueCode: 'rdl_excessive_knee_bend' },
        { lowercasedText: 'hinge deeper until you feel a stretch in your hamstrings', issueCode: 'rdl_shallow_hinge' },
        { lowercasedText: 'keep the bar sliding along your thighs the whole way down', issueCode: 'rdl_bar_drift' },
    ];
    // Spoken clean-set closers. Mirrors `SpeechPhraseCatalog.cleanClosers` in
    // SpeechPhrases.swift — keep both lists (and the id rule below) aligned or
    // the baked audio and the runtime matcher will drift.
    const cleanClosers = [
        { text: 'that set was dialed in', key: 'dialed_in' },
        { text: 'that one was perfect', key: 'perfect' },
        { text: 'you were locked in there', key: 'locked_in' },
        { text: 'clean work all the way', key: 'clean_work' },
        { text: 'that was textbook', key: 'textbook' },
        { text: 'really strong set', key: 'strong_set' },
    ];
    // Mirrors `SpeechPhraseCatalog.cleanFallbackPhraseId`: `dialed_in` keeps the
    // legacy un-suffixed id so previously baked audio still resolves.
    const cleanFallbackPhraseId = (bestKey, closerKey) =>
        closerKey === 'dialed_in'
            ? `fallback_clean_${bestKey}`
            : `fallback_clean_${bestKey}_${closerKey}`;

    for (const best of fallbackBestThings) {
        for (const closer of cleanClosers) {
            variations.push({
                id: cleanFallbackPhraseId(best.key, closer.key),
                text: `${best.text} — ${closer.text}`,
            });
        }
        variations.push({
            id: `fallback_corrective_no_cue_${best.key}`,
            text: `${best.text} — keep that same form`,
        });
        for (const cue of fallbackCues) {
            variations.push({
                id: `fallback_corrective_${best.key}_${cue.issueCode}`,
                text: `${best.text}, now ${cue.lowercasedText}`,
            });
        }
    }

    return variations;
}

/**
 * Main execution
 */
async function main() {
    console.log('🎙️  Starting speech asset generation...\n');
    
    const phrases = loadPhrases();
    console.log(`📋 Loaded ${phrases.length} phrases\n`);
    
    const manifest = {};
    const results = {
        success: 0,
        failed: 0,
        skipped: 0
    };
    
    for (let i = 0; i < phrases.length; i++) {
        const phrase = phrases[i];
        const result = await generateAudio(phrase.id, phrase.text);
        
        if (result.success) {
            if (result.skipped) {
                results.skipped++;
            } else {
                results.success++;
            }
            manifest[phrase.id] = `${phrase.id}.mp3`;
        } else {
            results.failed++;
            console.error(`   Failed to generate: ${phrase.id}`);
        }
        
        // Rate limiting delay (except for last item)
        if (i < phrases.length - 1) {
            await new Promise(resolve => setTimeout(resolve, DELAY_BETWEEN_REQUESTS));
        }
        
        // Progress indicator
        if ((i + 1) % 10 === 0) {
            console.log(`\n📊 Progress: ${i + 1}/${phrases.length} phrases processed\n`);
        }
    }
    
    // Save manifest
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`\n📄 Manifest saved to: ${manifestPath}`);
    
    // Summary
    console.log('\n' + '='.repeat(50));
    console.log('📊 Generation Summary:');
    console.log(`   ✅ Success: ${results.success}`);
    console.log(`   ⏭️  Skipped: ${results.skipped}`);
    console.log(`   ❌ Failed: ${results.failed}`);
    console.log(`   📁 Total files: ${Object.keys(manifest).length}`);
    console.log('='.repeat(50) + '\n');
    
    if (results.failed > 0) {
        console.warn('⚠️  Some phrases failed to generate. Check the errors above.');
        process.exit(1);
    } else {
        console.log('✨ All phrases generated successfully!');
    }
}

// Run the script
main().catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
});
