#!/usr/bin/env node

/**
 * Add missing speech phrases to the catalog
 * 
 * This script adds specific phrases that are needed but missing:
 * - "Rest, 45 seconds"
 * - "When you've completed 6 to 8 reps, press the arrow to move on"
 * 
 * It also updates the rest phrase generation to use 5-second increments
 * to match the Swift code.
 * 
 * Usage:
 *   OPENAI_API_KEY=your_key node add_missing_phrases.js
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

// Load existing manifest
let manifest = {};
if (fs.existsSync(manifestPath)) {
    try {
        manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
        console.log(`📋 Loaded existing manifest with ${Object.keys(manifest).length} phrases`);
    } catch (error) {
        console.warn(`⚠️  Could not load existing manifest: ${error.message}`);
    }
}

// Rate limiting delay
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
            console.log(`   Text: "${text}"`);
            
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
 * Main execution
 */
async function main() {
    console.log('🎙️  Adding missing speech phrases...\n');
    
    // Phrases to add - exactly as requested
    const allPhrases = [
        {
            id: 'rest_basic_45',
            text: 'Rest, 45 Seconds'
        },
        {
            id: 'workout_rep_reminder_6_to_8',
            text: "When you've completed 6 to 8 reps, press the arrow to move on"
        }
    ];
    console.log(`📋 Found ${allPhrases.length} phrases to add\n`);
    
    const results = {
        success: 0,
        failed: 0,
        skipped: 0,
        new: 0
    };
    
    for (let i = 0; i < allPhrases.length; i++) {
        const phrase = allPhrases[i];
        
        // Check if already in manifest
        if (manifest[phrase.id]) {
            console.log(`⏭️  Skipping ${phrase.id} (already in manifest)`);
            results.skipped++;
            continue;
        }
        
        const result = await generateAudio(phrase.id, phrase.text);
        
        if (result.success) {
            if (result.skipped) {
                results.skipped++;
            } else {
                results.success++;
                results.new++;
            }
            manifest[phrase.id] = `${phrase.id}.mp3`;
        } else {
            results.failed++;
            console.error(`   Failed to generate: ${phrase.id}`);
        }
        
        // Rate limiting delay (except for last item)
        if (i < allPhrases.length - 1) {
            await new Promise(resolve => setTimeout(resolve, DELAY_BETWEEN_REQUESTS));
        }
        
        // Progress indicator
        if ((i + 1) % 10 === 0) {
            console.log(`\n📊 Progress: ${i + 1}/${allPhrases.length} phrases processed\n`);
        }
    }
    
    // Save updated manifest
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`\n📄 Manifest saved to: ${manifestPath}`);
    console.log(`   Total phrases in manifest: ${Object.keys(manifest).length}`);
    
    // Summary
    console.log('\n' + '='.repeat(50));
    console.log('📊 Generation Summary:');
    console.log(`   ✅ New: ${results.new}`);
    console.log(`   ⏭️  Skipped: ${results.skipped}`);
    console.log(`   ❌ Failed: ${results.failed}`);
    console.log('='.repeat(50) + '\n');
    
    if (results.failed > 0) {
        console.warn('⚠️  Some phrases failed to generate. Check the errors above.');
        process.exit(1);
    } else {
        console.log('✨ All phrases added successfully!');
    }
}

// Run the script
main().catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
});
