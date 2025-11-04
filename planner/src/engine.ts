import type { 
  Inputs, 
  ProgramPlan, 
  Exercise, 
  ExerciseSelection, 
  WeekPlan, 
  DayPlan, 
  ExerciseCandidate, 
  TimeConfig,
  PlannedBlock,
  TimeBoundedPlan
} from './types';
import { TEMPLATES } from './templates';
import { weeklySetsByGoal, timePerExerciseMinutes } from './rules';
import { schemeFor } from './schemes';
import { isAllowed, modifiedSchemePenalty } from './injuries';
import { fitToTimeBudget, createMinimalPlan } from './fitToBudget';
import { DEFAULT_CONFIG } from './timeEstimator';

function stableSort<T>(arr: T[], cmp: (a: T, b: T) => number): T[] {
  return arr
    .map((v, i) => ({ v, i }))
    .sort((a, b) => {
      const c = cmp(a.v, b.v);
      return c !== 0 ? c : a.i - b.i;
    })
    .map(x => x.v);
}

export function generatePlan(input: Inputs, library: Exercise[]): ProgramPlan {
  // 1) Validate input; shallow defaults
  const schedule = input.schedule;
  const template = TEMPLATES.find(t => t.split === input.split) || TEMPLATES[0];
  const scheme = schemeFor(input.goal);

  // Use target_duration_minutes if provided, otherwise use schedule.sessionMinutes
  const targetDuration = input.target_duration_minutes || schedule.sessionMinutes;

  // 3) Weekly volume targets
  const volTarget = weeklySetsByGoal[input.goal];
  const targets = input.targetMuscles.length > 0 ? input.targetMuscles : ['chest','back','delts','quads','hams','glutes','calves','abs'] as Inputs['targetMuscles'];

  const weeks: WeekPlan[] = [];
  for (let w = 0; w < schedule.programWeeks; w++) {
    const days: DayPlan[] = [];
    for (const day of template.days) {
      // 4) Select exercises per day
      const allowed = library.filter(ex => isAllowed(ex, input.injuries));

      // Convert exercises to candidates for time-bounded planning
      const candidates: ExerciseCandidate[] = allowed.map((ex, index) => {
        const primaryMatch = ex.primaryMuscles.some(m => targets.includes(m as any)) ? 1 : 0;
        const secondaryMatch = ex.secondaryMuscles.some(m => targets.includes(m as any)) ? 1 : 0;
        const timeEfficiency = ex.flags.includes('time_efficient') ? 1 : 0;
        const patternCoverage = new Set(ex.primaryMuscles.concat(ex.secondaryMuscles)).size > 1 ? 1 : 0;
        const equipmentAvailability = ex.equipment.length > 0 ? 1 : 0;
        const score = 3*primaryMatch + 2*patternCoverage + 1*timeEfficiency + 1*equipmentAvailability + 0.5*secondaryMatch;
        
        // Determine category
        const category: 'compound' | 'isolation' | 'accessory' = 
          ex.pattern === 'isolation' ? 'isolation' : 'compound';
        
        // Calculate priority (lower = higher priority)
        const priority = Math.max(1, 10 - Math.floor(score * 2));
        
        // Get sets based on scheme and deload
        const isDeload = [3,7,11].includes(w);
        const pen = modifiedSchemePenalty(ex.pattern, input.injuries);
        const setsTarget = Math.max(2, Math.round(scheme.sets - pen - (isDeload ? scheme.sets*0.3 : 0)));
        const setsMin = Math.max(1, setsTarget - 1);
        
        return {
          id: ex.id,
          muscle_groups: [...ex.primaryMuscles, ...ex.secondaryMuscles],
          priority,
          sets_target: setsTarget,
          sets_min: setsMin,
          reps: scheme.reps,
          rest_seconds: scheme.restSec,
          superset_with: undefined, // Will be set later if needed
          category,
          pattern: ex.pattern,
        };
      });

      // Sort by priority for time-bounded planning
      candidates.sort((a, b) => a.priority - b.priority);

      // Prepare time config
      const timeConfig: TimeConfig = {
        target_duration_minutes: targetDuration,
        buffer_minutes: input.target_duration_minutes ? DEFAULT_CONFIG.buffer_minutes : 0,
        transition_seconds: input.transition_seconds || DEFAULT_CONFIG.transition_seconds,
        min_rest_accessory: DEFAULT_CONFIG.min_rest_accessory,
        warmup_max_minutes: input.warmup_policy?.max_minutes || DEFAULT_CONFIG.warmup_max_minutes,
        default_rest_seconds: input.default_rest_seconds || scheme.restSec,
      };

      // Handle supersets if enabled and session is short
      if (input.supersets && targetDuration < 45) {
        // Pair adjacent exercises for supersets
        for (let i = 0; i < candidates.length - 1; i += 2) {
          if (candidates[i].category !== 'compound' || candidates[i+1].category !== 'compound') {
            candidates[i].superset_with = candidates[i+1].id;
            candidates[i+1].superset_with = candidates[i].id;
          }
        }
      }

      // Apply variety policy
      let finalCandidates = candidates;
      if (input.variety !== 'consistent' && candidates.length > 0) {
        const offset = input.variety === 'balanced' ? (w % candidates.length) : ((w) % candidates.length);
        finalCandidates = candidates.map((_, i) => candidates[(i + offset) % candidates.length]);
      }

      // Use time-bounded planning
      let timeBoundedPlan: TimeBoundedPlan;
      
      // If time is extremely limited, create minimal plan
      if (targetDuration <= 20) {
        timeBoundedPlan = createMinimalPlan(finalCandidates, timeConfig, input.goal);
      } else {
        timeBoundedPlan = fitToTimeBudget(finalCandidates, timeConfig, input.goal);
      }

      // Convert PlannedBlocks back to ExerciseSelections
      const items: ExerciseSelection[] = timeBoundedPlan.planned_blocks
        .filter(block => block.estimated_minutes > 0) // Skip superset partner blocks with 0 time
        .map(block => {
          const candidate = finalCandidates.find(c => c.id === block.exercise_id);
          const reps = typeof block.reps === 'string' && block.reps.includes('-') 
            ? block.reps.split('-').map(Number) as [number, number]
            : typeof block.reps === 'number' 
            ? [block.reps, block.reps] as [number, number]
            : scheme.reps;
          
          return {
            exerciseId: block.exercise_id,
            scheme: {
              sets: block.sets,
              reps: reps,
              rpeCap: scheme.rpeCap,
              restSec: block.rest_seconds,
            },
            supersetWith: block.superset_with,
            estimated_minutes: block.estimated_minutes,
          };
        });

      days.push({ 
        dayIndex: day.dayIndex, 
        items, 
        estMinutes: timeBoundedPlan.total_planned_minutes,
        timeBoundedPlan
      });
    }
    weeks.push({ weekIndex: w+1, days, deload: [4,8,12].includes(w+1) });
  }

  return { meta: input, weeks };
}




