import type { ExerciseCandidate, TimeConfig, PlannedBlock, Goal } from './types';

// Default configuration (with generous margins - Option A: 10-15 min buffer + 20-30% padding)
export const DEFAULT_CONFIG = {
  buffer_minutes: 12,  // Increased from 5 to 12 minutes (generous margin)
  transition_seconds: 25,  // Keep at 25s but add 20% padding in calculations
  min_rest_accessory: 60,  // Increased from 45 to 60 seconds (more generous)
  warmup_max_minutes: 8,
  default_rest_seconds: 90,
} as const;

// Work time heuristics when tempo is not provided (with 30% padding for realistic set completion)
const WORK_TIME_HEURISTICS = {
  hypertrophy: 58,   // seconds per set (45 * 1.3 = 58.5, rounded)
  strength: 33,      // seconds per set (25 * 1.3 = 32.5, rounded)
  endurance: 78,     // seconds per set (60 * 1.3 = 78)
  compound: 78,     // seconds for complex compound sets (60 * 1.3 = 78)
  isolation: 52,    // seconds per set (40 * 1.3 = 52)
  accessory: 46,     // seconds per set (35 * 1.3 = 45.5, rounded)
} as const;

// Experience-based multipliers for additional time padding
const EXPERIENCE_MULTIPLIERS = {
  beginner: 1.5,    // +50% additional time (learning form, slower execution)
  novice: 1.3,      // +30% additional time
  intermediate: 1.15, // +15% additional time
  advanced: 1.0,     // Base time (most efficient)
} as const;

/**
 * Estimates work time for a single set
 */
export function estimateWorkTime(
  exercise: ExerciseCandidate,
  goal: Goal = 'hypertrophy',
  experienceLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' = 'intermediate'
): number {
  let baseTime: number;
  
  // If tempo is known, calculate precisely
  if (exercise.tempo_seconds_per_rep && typeof exercise.reps === 'number') {
    baseTime = exercise.reps * exercise.tempo_seconds_per_rep;
  } else {
    // Otherwise use heuristics based on exercise category and goal
    if (exercise.category === 'compound') {
      baseTime = goal === 'strength' ? WORK_TIME_HEURISTICS.strength : WORK_TIME_HEURISTICS.compound;
    } else if (exercise.category === 'isolation') {
      baseTime = WORK_TIME_HEURISTICS.isolation;
    } else {
      // accessory
      baseTime = WORK_TIME_HEURISTICS.accessory;
    }
  }
  
  // Apply experience-based multiplier
  const multiplier = EXPERIENCE_MULTIPLIERS[experienceLevel] || 1.0;
  return baseTime * multiplier;
}

/**
 * Estimates total minutes for a single exercise block
 */
export function estimateBlockMinutes(
  block: ExerciseCandidate | PlannedBlock,
  config: TimeConfig,
  goal: Goal = 'hypertrophy',
  includeTransition: boolean = true,
  experienceLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' = 'intermediate'
): number {
  const sets = 'sets' in block ? block.sets : block.sets_target;
  const rest_seconds = 'rest_seconds' in block ? block.rest_seconds : 
    (config.default_rest_seconds || DEFAULT_CONFIG.default_rest_seconds);
  
  // Calculate work time per set using estimateWorkTime with experience multiplier
  let workTimePerSet: number;
  if ('tempo_seconds_per_rep' in block && block.tempo_seconds_per_rep) {
    const reps = typeof block.reps === 'number' ? block.reps : 
      (Array.isArray(block.reps) ? block.reps[1] : 10); // use max reps if range
    const baseTime = reps * block.tempo_seconds_per_rep;
    // Apply experience multiplier
    const multiplier = EXPERIENCE_MULTIPLIERS[experienceLevel] || 1.0;
    workTimePerSet = baseTime * multiplier;
  } else {
    // Use heuristics with experience multiplier
    const category = 'category' in block ? block.category : 'isolation';
    if (category === 'compound') {
      workTimePerSet = goal === 'strength' ? WORK_TIME_HEURISTICS.strength : WORK_TIME_HEURISTICS.compound;
    } else if (category === 'isolation') {
      workTimePerSet = WORK_TIME_HEURISTICS.isolation;
    } else {
      workTimePerSet = WORK_TIME_HEURISTICS.accessory;
    }
    // Apply experience multiplier
    const multiplier = EXPERIENCE_MULTIPLIERS[experienceLevel] || 1.0;
    workTimePerSet = workTimePerSet * multiplier;
  }
  
  // Total time = (work time * sets) + (rest time * (sets - 1)) + transition (with 20% padding on transition)
  const totalWorkTime = workTimePerSet * sets;
  const totalRestTime = rest_seconds * Math.max(0, sets - 1); // No rest after last set
  const transitionTime = includeTransition ? 
    ((config.transition_seconds || DEFAULT_CONFIG.transition_seconds) * 1.2) : 0; // 20% padding on transition
  
  const totalSeconds = totalWorkTime + totalRestTime + transitionTime;
  return totalSeconds / 60; // Convert to minutes
}

/**
 * Estimates time for a superset block (two exercises performed back-to-back)
 */
export function estimateSupersetMinutes(
  exerciseA: ExerciseCandidate,
  exerciseB: ExerciseCandidate,
  config: TimeConfig,
  goal: Goal = 'hypertrophy',
  experienceLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' = 'intermediate'
): number {
  const setsA = exerciseA.sets_target;
  const setsB = exerciseB.sets_target;
  const sets = Math.max(setsA, setsB); // Supersets use the max sets
  
  // Work time is sum of both exercises (with experience multipliers)
  const workTimeA = estimateWorkTime(exerciseA, goal, experienceLevel);
  const workTimeB = estimateWorkTime(exerciseB, goal, experienceLevel);
  const combinedWorkTime = workTimeA + workTimeB;
  
  // Rest only after the pair
  const rest_seconds = exerciseA.rest_seconds || config.default_rest_seconds || DEFAULT_CONFIG.default_rest_seconds;
  
  // Total time calculation (with 20% padding on transition)
  const totalWorkTime = combinedWorkTime * sets;
  const totalRestTime = rest_seconds * Math.max(0, sets - 1);
  const transitionTime = (config.transition_seconds || DEFAULT_CONFIG.transition_seconds) * 1.2; // 20% padding
  
  const totalSeconds = totalWorkTime + totalRestTime + transitionTime;
  return totalSeconds / 60;
}

/**
 * Estimates time for a circuit block (multiple exercises in sequence)
 */
export function estimateCircuitMinutes(
  exercises: ExerciseCandidate[],
  config: TimeConfig,
  goal: Goal = 'hypertrophy',
  circuitRounds: number = 3
): number {
  if (exercises.length === 0) return 0;
  
  // Calculate total work time for one circuit round
  let workTimePerRound = 0;
  for (const exercise of exercises) {
    workTimePerRound += estimateWorkTime(exercise, goal);
  }
  
  // Rest between rounds
  const rest_seconds = config.default_rest_seconds || DEFAULT_CONFIG.default_rest_seconds;
  const totalWorkTime = workTimePerRound * circuitRounds;
  const totalRestTime = rest_seconds * Math.max(0, circuitRounds - 1);
  const transitionTime = config.transition_seconds || DEFAULT_CONFIG.transition_seconds;
  
  const totalSeconds = totalWorkTime + totalRestTime + transitionTime;
  return totalSeconds / 60;
}

/**
 * Estimates warmup time based on policy and workout intensity
 */
export function estimateWarmupMinutes(
  config: TimeConfig,
  isHeavyDay: boolean = false
): number {
  if (!config.warmup_policy?.include) return 0;
  
  const maxMinutes = config.warmup_policy.max_minutes || config.warmup_max_minutes || DEFAULT_CONFIG.warmup_max_minutes;
  const baseMinutes = isHeavyDay ? 6 : 5;
  
  return Math.min(baseMinutes, maxMinutes);
}

/**
 * Estimates cooldown time based on policy
 */
export function estimateCooldownMinutes(config: TimeConfig): number {
  if (!config.cooldown_policy?.include) return 0;
  return config.cooldown_policy.minutes || 3;
}

/**
 * Calculates total session time for a complete workout
 */
export function calculateTotalSessionMinutes(
  blocks: PlannedBlock[],
  config: TimeConfig
): number {
  let total = 0;
  
  // Add warmup
  total += estimateWarmupMinutes(config);
  
  // Add all exercise blocks
  for (const block of blocks) {
    total += block.estimated_minutes;
  }
  
  // Add cooldown
  total += estimateCooldownMinutes(config);
  
  // Add buffer
  total += config.buffer_minutes || DEFAULT_CONFIG.buffer_minutes;
  
  return total;
}

/**
 * Creates a debug breakdown of time allocation
 */
export function createTimeBreakdown(
  blocks: PlannedBlock[],
  config: TimeConfig
): Record<string, number> {
  const warmup = estimateWarmupMinutes(config);
  const cooldown = estimateCooldownMinutes(config);
  const buffer = config.buffer_minutes || DEFAULT_CONFIG.buffer_minutes;
  const exercises = blocks.reduce((sum, b) => sum + b.estimated_minutes, 0);
  const total = warmup + exercises + cooldown + buffer;
  
  return {
    warmup_minutes: warmup,
    exercise_minutes: exercises,
    cooldown_minutes: cooldown,
    buffer_minutes: buffer,
    total_minutes: total,
    num_exercises: blocks.length,
    transition_seconds: config.transition_seconds || DEFAULT_CONFIG.transition_seconds,
  };
}
