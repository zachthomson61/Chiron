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
 * Load phrases from the catalog
 * For now, we'll use a hardcoded list based on SpeechPhrases.swift
 * In the future, this could parse the Swift file or read a JSON export
 */
function loadPhrases() {
    // Static phrases from SpeechPhrases.swift
    const staticPhrases = [
        // Encouragement
        { id: 'encouragement_great_job', text: 'Great job!' },
        { id: 'encouragement_perfect_form', text: 'Perfect form!' },
        { id: 'encouragement_keep_it_up', text: 'Keep it up!' },
        { id: 'encouragement_nice_work', text: 'Nice work!' },
        { id: 'encouragement_excellent', text: 'Excellent!' },
        { id: 'encouragement_good_depth', text: 'Good depth' },
        { id: 'encouragement_perfect_tempo', text: 'Perfect tempo' },
        { id: 'encouragement_well_done', text: 'Well done!' },
        { id: 'encouragement_keep_going', text: 'Keep going!' },
        { id: 'encouragement_doing_great', text: "You're doing great!" },
        { id: 'encouragement_stay_focused', text: 'Stay focused!' },
        { id: 'encouragement_good_form', text: 'Good form' },
        { id: 'encouragement_excellent_depth', text: 'Excellent depth' },
        { id: 'encouragement_perfect_alignment', text: 'Perfect alignment' },
        { id: 'encouragement_nice_work_there', text: 'Nice work there' },
        { id: 'encouragement_good_control', text: 'Good control' },
        { id: 'encouragement_solid_effort', text: 'Solid effort' },
        { id: 'encouragement_that_was_better', text: 'That was better' },
        { id: 'encouragement_keep_that_up', text: 'Keep that up' },
        { id: 'encouragement_i_like_that', text: 'I like that' },
        { id: 'encouragement_much_better', text: 'Much better' },
        { id: 'encouragement_getting_stronger', text: 'Getting stronger' },
        { id: 'encouragement_nice_improvement', text: 'Nice improvement' },
        
        // Rep Feedback
        { id: 'rep_feedback_great_rep', text: 'Great rep! ' },
        { id: 'rep_feedback_good_rep', text: 'Good rep. ' },
        { id: 'rep_feedback_try_deeper', text: 'Try going deeper next time. ' },
        { id: 'rep_feedback_keep_chest_up', text: 'Keep that chest up. ' },
        { id: 'rep_feedback_keep_form', text: 'Keep that form! ' },
        
        // Analysis Feedback
        { id: 'analysis_complete', text: 'Analysis complete. ' },
        { id: 'analysis_one_rep', text: "You completed one rep - let's build on that. " },
        { id: 'analysis_keep_up_good_work', text: 'Keep up the good work. ' },
        
        // Exercise Setup Cues
        { id: 'exercise_setup_bodyweight_squat', text: 'Go slow and controlled on the way down. Keep your chest tall and core tight' },
        { id: 'exercise_setup_barbell_back_squat', text: 'Position the barbell across your upper traps. Keep the bar path vertical over mid foot. Brace your core before each descent' },
        { id: 'exercise_setup_barbell_row', text: 'Position yourself with feet hip-width apart. Hinge at the hips and keep your spine neutral' },
        { id: 'exercise_setup_deadlift', text: 'Position the bar over mid foot. Keep your chest up and spine neutral throughout the movement' },
        { id: 'exercise_setup_romanian_deadlift', text: 'Stand tall with feet hip-width. Keep your knees slightly bent and maintain a neutral spine' },
        { id: 'exercise_setup_barbell_bench_press', text: 'Position yourself on the bench with feet flat on the floor. Keep your shoulder blades retracted' },
        { id: 'exercise_start_workout', text: "Let's get it!" },
        
        // Camera Setup
        { id: 'camera_setup_prompt', text: "Let's setup your camera for live coaching! Select the view you would like to use." },
        { id: 'camera_setup_rack', text: 'For a mount setup, mount your phone high up on one of the front rack posts, angled down toward the middle of the bar. Center the frame on the bar and your hands, not your face. Keep your full arm length and bar path visible. Try to avoid cropping at lockout or when you touch your chest.' },
        { id: 'camera_setup_floor', text: 'For a floor setup, place your phone on the floor, 4 to 6 feet from the bench, angled slightly upwards. Center it on the bar. Make sure to keep your hands, elbows, and bar path in frame.' },
        { id: 'camera_setup_tripod', text: 'For a tripod setup, place the tripod 2 to 3 feet in front of the bench, centered on the bar. Ensure that the tripod is at the same height as the racked bar or slightly higher. Angle the camera slightly down towards your grip. Ensure your hands, elbows, and bar path are in view.' },
        
        // Workout Flow
        { id: 'workout_30_seconds_left', text: '30 Seconds Left' },
        { id: 'workout_10_seconds_left', text: '10 Seconds Left' },
    ];
    
    // Generate dynamic variations
    const dynamicPhrases = [];
    
    // Exercise-specific phrases from Python Wrangler workout
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
        '10 to 12 reps'
    ];
    
    function sanitizeForId(text) {
        return text.toLowerCase()
            .replace(/\s+/g, '_')
            .replace(/-/g, '_')
            .replace(/,/g, '')
            .replace(/\./g, '')
            .replace(/\(/g, '')
            .replace(/\)/g, '');
    }
    
    // Generate "First up" phrases
    for (const exercise of exercises) {
        const fullName = exercise.side ? `${exercise.name} - ${exercise.side}` : exercise.name;
        for (const repTime of repTimeFormats) {
            const phraseId = `workout_first_up_${sanitizeForId(fullName)}_${sanitizeForId(repTime)}`;
            const phraseText = `First up, ${fullName}, ${repTime}`;
            dynamicPhrases.push({ id: phraseId, text: phraseText });
        }
    }
    
    // Generate "Next up" phrases
    for (const exercise of exercises) {
        const fullName = exercise.side ? `${exercise.name} - ${exercise.side}` : exercise.name;
        for (const repTime of repTimeFormats) {
            const phraseId = `workout_next_up_${sanitizeForId(fullName)}_${sanitizeForId(repTime)}`;
            const phraseText = `Next up, ${fullName}, ${repTime}`;
            dynamicPhrases.push({ id: phraseId, text: phraseText });
        }
    }
    
    // Generate exercise guide phrases (without "First up" or "Next up")
    for (const exercise of exercises) {
        const fullName = exercise.side ? `${exercise.name} - ${exercise.side}` : exercise.name;
        for (const repTime of repTimeFormats) {
            const phraseId = `workout_exercise_${sanitizeForId(fullName)}_${sanitizeForId(repTime)}`;
            const phraseText = `${fullName}, ${repTime}`;
            dynamicPhrases.push({ id: phraseId, text: phraseText });
        }
    }
    
    // Rest announcements: 10-300 seconds in 10-second increments
    for (let duration = 10; duration <= 300; duration += 10) {
        dynamicPhrases.push({ id: `rest_basic_${duration}`, text: `Rest, ${duration} Seconds` });
        dynamicPhrases.push({ id: `rest_you_deserve_it_${duration}`, text: `Rest, ${duration} Seconds. You deserve it!` });
        dynamicPhrases.push({ id: `rest_stretch_${duration}`, text: `Rest, ${duration} Seconds. Stretch out a bit.` });
        dynamicPhrases.push({ id: `rest_drink_water_${duration}`, text: `Rest, ${duration} Seconds. Take a drink of water if you're thirsty.` });
        dynamicPhrases.push({ id: `rest_recover_next_set_${duration}`, text: `Rest, ${duration} Seconds. Recover and then let's get this next set!` });
    }
    
    // Rep reminders: 1-20 reps
    for (let count = 1; count <= 20; count++) {
        dynamicPhrases.push({ id: `workout_rep_reminder_${count}`, text: `When you've completed ${count} reps, press the arrow to move on` });
    }
    
    // Analysis score variations: 0-100 in increments of 5
    for (let score = 0; score <= 100; score += 5) {
        dynamicPhrases.push({ id: `analysis_excellent_work_${score}`, text: `Excellent work! You scored ${score} percent. ` });
        dynamicPhrases.push({ id: `analysis_good_job_${score}`, text: `Good job! Your form score was ${score} percent. ` });
        dynamicPhrases.push({ id: `analysis_work_on_improving_${score}`, text: `Your form score was ${score} percent - let's work on improving that. ` });
    }
    
    // Analysis rep count variations: 1-20 reps
    for (let count = 1; count <= 20; count++) {
        dynamicPhrases.push({ id: `analysis_completed_solid_reps_${count}`, text: `You completed ${count} solid reps. ` });
        dynamicPhrases.push({ id: `analysis_nice_work_reps_${count}`, text: `Nice work on those ${count} reps. ` });
    }
    
    return [...staticPhrases, ...dynamicPhrases];
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
