import type { 
  ExerciseCandidate, 
  TimeConfig, 
  PlannedBlock, 
  TimeBoundedPlan,
  DebugPlan,
  Goal 
} from './types';
import { 
  estimateBlockMinutes, 
  estimateSupersetMinutes, 
  estimateWarmupMinutes,
  estimateCooldownMinutes,
  DEFAULT_CONFIG 
} from './timeEstimator';

/**
 * Main function to fit exercises to time budget using greedy algorithm
 */
export function fitToTimeBudget(
  candidates: ExerciseCandidate[],
  config: TimeConfig,
  goal: Goal = 'hypertrophy',
  experienceLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' = 'intermediate'
): TimeBoundedPlan {
  const debugSteps: string[] = [];
  const targetMinutes = config.target_duration_minutes;
  
  // Initialize time allocations
  const bufferMinutes = config.buffer_minutes || DEFAULT_CONFIG.buffer_minutes;
  const warmupMinutes = estimateWarmupMinutes(config);
  const cooldownMinutes = estimateCooldownMinutes(config);
  const transitionSeconds = config.transition_seconds || DEFAULT_CONFIG.transition_seconds;
  
  // Calculate available time for exercises
  let availableMinutes = targetMinutes - bufferMinutes - warmupMinutes - cooldownMinutes;
  
  debugSteps.push(`Target: ${targetMinutes}min, Buffer: ${bufferMinutes}min, Warmup: ${warmupMinutes}min, Cooldown: ${cooldownMinutes}min`);
  debugSteps.push(`Available for exercises: ${availableMinutes.toFixed(1)}min`);
  
  // Sort candidates by priority (ascending - lower number = higher priority)
  // Then by category (compound > isolation > accessory)
  const sortedCandidates = [...candidates].sort((a, b) => {
    if (a.priority !== b.priority) return a.priority - b.priority;
    
    // Category priority: compound > isolation > accessory
    const categoryOrder = { compound: 0, isolation: 1, accessory: 2 };
    const orderA = categoryOrder[a.category] ?? 2;
    const orderB = categoryOrder[b.category] ?? 2;
    return orderA - orderB;
  });
  
  // Greedy algorithm: add exercises while they fit
  const plannedBlocks: PlannedBlock[] = [];
  let currentMinutes = 0;
  const supersetPairs = new Map<string, ExerciseCandidate>();
  
  // First, identify superset pairs
  for (const candidate of sortedCandidates) {
    if (candidate.superset_with) {
      const partner = sortedCandidates.find(c => c.id === candidate.superset_with);
      if (partner && !supersetPairs.has(candidate.id)) {
        supersetPairs.set(candidate.id, partner);
        supersetPairs.set(partner.id, candidate);
      }
    }
  }
  
  const processedIds = new Set<string>();
  
  for (const candidate of sortedCandidates) {
    if (processedIds.has(candidate.id)) continue;
    
    let blockMinutes: number;
    let block: PlannedBlock;
    
    // Check if this is part of a superset
    if (supersetPairs.has(candidate.id) && config.allow_supersets !== false) {
      const partner = supersetPairs.get(candidate.id)!;
      if (processedIds.has(partner.id)) continue;
      
      blockMinutes = estimateSupersetMinutes(candidate, partner, config, goal, experienceLevel);
      
      if (currentMinutes + blockMinutes <= availableMinutes) {
        block = {
          exercise_id: candidate.id,
          sets: candidate.sets_target,
          reps: typeof candidate.reps === 'number' ? candidate.reps : `${candidate.reps[0]}-${candidate.reps[1]}`,
          rest_seconds: candidate.rest_seconds,
          estimated_minutes: blockMinutes,
          superset_with: partner.id,
          notes: `Superset with ${partner.id}`,
        };
        
        plannedBlocks.push(block);
        
        // Also add the partner as a separate block for clarity
        plannedBlocks.push({
          exercise_id: partner.id,
          sets: partner.sets_target,
          reps: typeof partner.reps === 'number' ? partner.reps : `${partner.reps[0]}-${partner.reps[1]}`,
          rest_seconds: partner.rest_seconds,
          estimated_minutes: 0, // Time counted in the main superset block
          notes: `Superset pair`,
        });
        
        currentMinutes += blockMinutes;
        processedIds.add(candidate.id);
        processedIds.add(partner.id);
        
        debugSteps.push(`Added superset ${candidate.id} + ${partner.id}: ${blockMinutes.toFixed(1)}min`);
      }
    } else {
      // Regular single exercise
      blockMinutes = estimateBlockMinutes(candidate, config, goal, true, experienceLevel);
      
      if (currentMinutes + blockMinutes <= availableMinutes) {
        block = {
          exercise_id: candidate.id,
          sets: candidate.sets_target,
          reps: typeof candidate.reps === 'number' ? candidate.reps : `${candidate.reps[0]}-${candidate.reps[1]}`,
          rest_seconds: candidate.rest_seconds,
          estimated_minutes: blockMinutes,
          notes: candidate.category === 'compound' ? 'cornerstone compound' : candidate.category,
        };
        
        plannedBlocks.push(block);
        currentMinutes += blockMinutes;
        processedIds.add(candidate.id);
        
        debugSteps.push(`Added ${candidate.id} sets=${candidate.sets_target} time=${blockMinutes.toFixed(1)}min`);
      } else {
        debugSteps.push(`Skipped ${candidate.id} (would exceed budget by ${(currentMinutes + blockMinutes - availableMinutes).toFixed(1)}min)`);
      }
    }
  }
  
  // If we're over budget, trim the plan
  if (currentMinutes > availableMinutes) {
    const trimResult = shrinkPlan(plannedBlocks, candidates, availableMinutes, config, goal, debugSteps, experienceLevel);
    return createPlanOutput(trimResult.blocks, warmupMinutes, cooldownMinutes, bufferMinutes, transitionSeconds, trimResult.debugSteps);
  }
  
  return createPlanOutput(plannedBlocks, warmupMinutes, cooldownMinutes, bufferMinutes, transitionSeconds, debugSteps);
}

/**
 * Shrinks a plan that exceeds the time budget
 */
function shrinkPlan(
  blocks: PlannedBlock[],
  originalCandidates: ExerciseCandidate[],
  targetMinutes: number,
  config: TimeConfig,
  goal: Goal,
  debugSteps: string[],
  experienceLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' = 'intermediate'
): { blocks: PlannedBlock[], debugSteps: string[] } {
  let currentBlocks = [...blocks];
  let currentMinutes = blocks.reduce((sum, b) => sum + b.estimated_minutes, 0);
  
  debugSteps.push(`Starting trim: ${currentMinutes.toFixed(1)}min -> target ${targetMinutes.toFixed(1)}min`);
  
  // Create a map for quick candidate lookup
  const candidateMap = new Map(originalCandidates.map(c => [c.id, c]));
  
  // Step 1: Remove sets from lowest priority accessories above sets_min
  const accessoryBlocks = currentBlocks
    .filter(b => {
      const candidate = candidateMap.get(b.exercise_id);
      return candidate && candidate.category !== 'compound' && b.sets > candidate.sets_min;
    })
    .sort((a, b) => {
      const candA = candidateMap.get(a.exercise_id)!;
      const candB = candidateMap.get(b.exercise_id)!;
      return candB.priority - candA.priority; // Lowest priority first
    });
  
  for (const block of accessoryBlocks) {
    if (currentMinutes <= targetMinutes) break;
    
    const candidate = candidateMap.get(block.exercise_id)!;
    const setsToRemove = Math.min(1, block.sets - candidate.sets_min);
    
    if (setsToRemove > 0) {
      const oldMinutes = block.estimated_minutes;
      block.sets -= setsToRemove;
        block.estimated_minutes = estimateBlockMinutes(
          { ...candidate, sets_target: block.sets },
          config,
          goal,
          true,
          experienceLevel
        );
      const saved = oldMinutes - block.estimated_minutes;
      currentMinutes -= saved;
      
      debugSteps.push(`Removed ${setsToRemove} set from ${block.exercise_id} to fit budget (saved ${saved.toFixed(1)}min)`);
    }
  }
  
  // Step 2: Reduce rest on accessories to floor
  if (currentMinutes > targetMinutes) {
    const minRestAccessory = config.min_rest_accessory || DEFAULT_CONFIG.min_rest_accessory;
    
    for (const block of currentBlocks) {
      if (currentMinutes <= targetMinutes) break;
      
      const candidate = candidateMap.get(block.exercise_id);
      if (candidate && candidate.category !== 'compound' && block.rest_seconds > minRestAccessory) {
        const oldMinutes = block.estimated_minutes;
        const oldRest = block.rest_seconds;
        block.rest_seconds = minRestAccessory;
        
        // Recalculate time with new rest
        block.estimated_minutes = estimateBlockMinutes(
          { ...candidate, sets_target: block.sets, rest_seconds: block.rest_seconds },
          config,
          goal,
          true,
          experienceLevel
        );
        
        const saved = oldMinutes - block.estimated_minutes;
        currentMinutes -= saved;
        
        debugSteps.push(`Reduced rest on ${block.exercise_id} from ${oldRest}s to ${minRestAccessory}s (saved ${saved.toFixed(1)}min)`);
      }
    }
  }
  
  // Step 3: Drop lowest priority accessories entirely
  if (currentMinutes > targetMinutes) {
    const sortedAccessories = currentBlocks
      .filter(b => {
        const candidate = candidateMap.get(b.exercise_id);
        return candidate && candidate.category !== 'compound';
      })
      .sort((a, b) => {
        const candA = candidateMap.get(a.exercise_id)!;
        const candB = candidateMap.get(b.exercise_id)!;
        return candB.priority - candA.priority;
      });
    
    for (const block of sortedAccessories) {
      if (currentMinutes <= targetMinutes) break;
      
      const index = currentBlocks.indexOf(block);
      if (index !== -1) {
        currentMinutes -= block.estimated_minutes;
        currentBlocks.splice(index, 1);
        debugSteps.push(`Dropped ${block.exercise_id} entirely to fit budget (saved ${block.estimated_minutes.toFixed(1)}min)`);
      }
    }
  }
  
  // Step 4: If still over, reduce warmup (but keep minimum safety threshold)
  if (currentMinutes > targetMinutes && config.warmup_policy?.include) {
    const minWarmup = 3; // Minimum safe warmup
    const currentWarmup = estimateWarmupMinutes(config);
    
    if (currentWarmup > minWarmup) {
      const reduction = Math.min(currentWarmup - minWarmup, currentMinutes - targetMinutes);
      config.warmup_policy.max_minutes = currentWarmup - reduction;
      debugSteps.push(`Reduced warmup by ${reduction.toFixed(1)}min to fit budget`);
    }
  }
  
  return { blocks: currentBlocks, debugSteps };
}

/**
 * Creates the final plan output with debug information
 */
function createPlanOutput(
  blocks: PlannedBlock[],
  warmupMinutes: number,
  cooldownMinutes: number,
  bufferMinutes: number,
  transitionSeconds: number,
  debugSteps: string[]
): TimeBoundedPlan {
  const exerciseMinutes = blocks.reduce((sum, b) => sum + b.estimated_minutes, 0);
  const totalMinutes = warmupMinutes + exerciseMinutes + cooldownMinutes;
  
  const debugPlan: DebugPlan = {
    budget_minutes: warmupMinutes + exerciseMinutes + cooldownMinutes + bufferMinutes,
    buffer_minutes: bufferMinutes,
    warmup_minutes: warmupMinutes,
    cooldown_minutes: cooldownMinutes,
    transition_seconds_per_change: transitionSeconds,
    sizing_steps: debugSteps,
  };
  
  return {
    total_planned_minutes: Math.round(totalMinutes * 10) / 10, // Round to 1 decimal
    planned_blocks: blocks,
    debug_plan: debugPlan,
  };
}

/**
 * Validates that a plan meets the time budget
 */
export function validateTimeBudget(
  plan: TimeBoundedPlan,
  targetMinutes: number,
  tolerance: number = 3
): { valid: boolean; message?: string } {
  if (plan.total_planned_minutes > targetMinutes) {
    return {
      valid: false,
      message: `Plan exceeds budget: ${plan.total_planned_minutes}min > ${targetMinutes}min`,
    };
  }
  
  if (plan.total_planned_minutes < targetMinutes - tolerance) {
    const underBy = targetMinutes - plan.total_planned_minutes;
    if (underBy > 5) {
      return {
        valid: false,
        message: `Plan significantly under budget: ${plan.total_planned_minutes}min (${underBy.toFixed(1)}min under)`,
      };
    }
  }
  
  return { valid: true };
}

/**
 * Creates a minimal safe plan when time is extremely limited
 */
export function createMinimalPlan(
  candidates: ExerciseCandidate[],
  config: TimeConfig,
  goal: Goal = 'hypertrophy',
  experienceLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' = 'intermediate'
): TimeBoundedPlan {
  const debugSteps: string[] = ['Creating minimal safe plan due to time constraints'];
  
  // Find one compound and one accessory
  const compound = candidates.find(c => c.category === 'compound');
  const accessory = candidates.find(c => c.category !== 'compound');
  
  const blocks: PlannedBlock[] = [];
  
  if (compound) {
    const compoundBlock: PlannedBlock = {
      exercise_id: compound.id,
      sets: compound.sets_min,
      reps: typeof compound.reps === 'number' ? compound.reps : `${compound.reps[0]}-${compound.reps[1]}`,
      rest_seconds: compound.rest_seconds,
      estimated_minutes: estimateBlockMinutes({ ...compound, sets_target: compound.sets_min }, config, goal, true, experienceLevel),
      notes: 'Minimal cornerstone compound',
    };
    blocks.push(compoundBlock);
    debugSteps.push(`Added minimal compound: ${compound.id}`);
  }
  
  if (accessory && config.target_duration_minutes >= 20) {
    const accessoryBlock: PlannedBlock = {
      exercise_id: accessory.id,
      sets: accessory.sets_min,
      reps: typeof accessory.reps === 'number' ? accessory.reps : `${accessory.reps[0]}-${accessory.reps[1]}`,
      rest_seconds: Math.min(accessory.rest_seconds, 60),
      estimated_minutes: estimateBlockMinutes(
        { ...accessory, sets_target: accessory.sets_min, rest_seconds: 60 },
        config,
        goal,
        true,
        experienceLevel
      ),
      notes: 'Minimal accessory',
    };
    blocks.push(accessoryBlock);
    debugSteps.push(`Added minimal accessory: ${accessory.id}`);
  }
  
  // Minimal warmup for safety
  const warmupMinutes = Math.min(3, estimateWarmupMinutes(config));
  const cooldownMinutes = 0; // Skip cooldown in extreme time constraints
  const bufferMinutes = Math.min(2, config.buffer_minutes || DEFAULT_CONFIG.buffer_minutes);
  
  return createPlanOutput(blocks, warmupMinutes, cooldownMinutes, bufferMinutes, config.transition_seconds || DEFAULT_CONFIG.transition_seconds, debugSteps);
}
