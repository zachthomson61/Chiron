import { describe, test, expect } from 'vitest';
import {
  fitToTimeBudget,
  validateTimeBudget,
  createMinimalPlan
} from '../src/fitToBudget';
import type { ExerciseCandidate, TimeConfig } from '../src/types';

describe('fitToBudget', () => {
  describe('fitToTimeBudget', () => {
    test('fits exercises within time budget', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'barbell_squat',
          muscle_groups: ['quads', 'glutes'],
          priority: 1,
          sets_target: 4,
          sets_min: 3,
          reps: 5,
          tempo_seconds_per_rep: 3,
          rest_seconds: 180,
          category: 'compound'
        },
        {
          id: 'bench_press',
          muscle_groups: ['chest', 'triceps'],
          priority: 1,
          sets_target: 4,
          sets_min: 3,
          reps: 5,
          tempo_seconds_per_rep: 3,
          rest_seconds: 180,
          category: 'compound'
        },
        {
          id: 'pullup',
          muscle_groups: ['back', 'biceps'],
          priority: 2,
          sets_target: 3,
          sets_min: 2,
          reps: 8,
          rest_seconds: 120,
          category: 'compound'
        },
        {
          id: 'lateral_raise',
          muscle_groups: ['delts'],
          priority: 4,
          sets_target: 3,
          sets_min: 2,
          reps: 15,
          rest_seconds: 60,
          category: 'isolation'
        },
        {
          id: 'bicep_curl',
          muscle_groups: ['biceps'],
          priority: 5,
          sets_target: 3,
          sets_min: 2,
          reps: 12,
          rest_seconds: 60,
          category: 'isolation'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 45,
        buffer_minutes: 5,
        transition_seconds: 25,
        warmup_policy: {
          include: true,
          max_minutes: 8
        },
        cooldown_policy: {
          include: false,
          minutes: 0
        }
      };

      const plan = fitToTimeBudget(candidates, config, 'strength');

      // Should fit within budget
      expect(plan.total_planned_minutes).toBeLessThanOrEqual(45);
      expect(plan.total_planned_minutes).toBeGreaterThanOrEqual(35); // Not too under

      // Should prioritize compounds first
      const exerciseIds = plan.planned_blocks.map(b => b.exercise_id);
      expect(exerciseIds).toContain('barbell_squat');
      expect(exerciseIds).toContain('bench_press');

      // Debug plan should be populated
      expect(plan.debug_plan.sizing_steps.length).toBeGreaterThan(0);
      expect(plan.debug_plan.budget_minutes).toBeCloseTo(45, 0);
    });

    test('handles supersets correctly', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'bench_press',
          muscle_groups: ['chest'],
          priority: 1,
          sets_target: 3,
          sets_min: 2,
          reps: 10,
          tempo_seconds_per_rep: 2,
          rest_seconds: 75,
          superset_with: 'bent_row',
          category: 'compound'
        },
        {
          id: 'bent_row',
          muscle_groups: ['back'],
          priority: 1,
          sets_target: 3,
          sets_min: 2,
          reps: 10,
          tempo_seconds_per_rep: 2,
          rest_seconds: 75,
          superset_with: 'bench_press',
          category: 'compound'
        },
        {
          id: 'squat',
          muscle_groups: ['quads'],
          priority: 2,
          sets_target: 3,
          sets_min: 2,
          reps: 8,
          rest_seconds: 120,
          category: 'compound'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 30,
        allow_supersets: true,
        buffer_minutes: 3,
        warmup_policy: {
          include: true,
          max_minutes: 5
        }
      };

      const plan = fitToTimeBudget(candidates, config);

      // Should create superset
      const benchBlock = plan.planned_blocks.find(b => b.exercise_id === 'bench_press');
      expect(benchBlock?.superset_with).toBe('bent_row');
      expect(benchBlock?.notes).toContain('Superset');

      // Both exercises should be in the plan
      const exerciseIds = plan.planned_blocks.map(b => b.exercise_id);
      expect(exerciseIds).toContain('bench_press');
      expect(exerciseIds).toContain('bent_row');
    });

    test('trims plan when over budget', () => {
      // Create many exercises that won't all fit
      const candidates: ExerciseCandidate[] = [];
      for (let i = 1; i <= 10; i++) {
        candidates.push({
          id: `exercise_${i}`,
          muscle_groups: ['various'],
          priority: Math.ceil(i / 2), // 1,1,2,2,3,3...
          sets_target: 4,
          sets_min: 2,
          reps: 10,
          rest_seconds: 90,
          category: i <= 3 ? 'compound' : 'isolation'
        });
      }

      const config: TimeConfig = {
        target_duration_minutes: 30, // Very limited time
        buffer_minutes: 3,
        warmup_policy: {
          include: true,
          max_minutes: 5
        }
      };

      const plan = fitToTimeBudget(candidates, config);

      // Should stay within budget
      expect(plan.total_planned_minutes).toBeLessThanOrEqual(30);

      // Should keep high priority exercises
      const exerciseIds = plan.planned_blocks.map(b => b.exercise_id);
      expect(exerciseIds).toContain('exercise_1');
      expect(exerciseIds).toContain('exercise_2');

      // Should have trimming steps in debug
      const hasTrimSteps = plan.debug_plan.sizing_steps.some(
        step => step.includes('Skipped') || step.includes('removed') || step.includes('Reduced')
      );
      expect(hasTrimSteps).toBe(true);
    });

    test('respects minimum sets constraint', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'squat',
          muscle_groups: ['quads'],
          priority: 1,
          sets_target: 5,
          sets_min: 3, // Must keep at least 3 sets
          reps: 5,
          rest_seconds: 180,
          category: 'compound'
        },
        {
          id: 'leg_curl',
          muscle_groups: ['hamstrings'],
          priority: 3,
          sets_target: 4,
          sets_min: 2, // Must keep at least 2 sets
          reps: 12,
          rest_seconds: 60,
          category: 'isolation'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 20, // Very tight budget
        buffer_minutes: 2
      };

      const plan = fitToTimeBudget(candidates, config);

      // If squat is included, it should have at least sets_min
      const squatBlock = plan.planned_blocks.find(b => b.exercise_id === 'squat');
      if (squatBlock) {
        expect(squatBlock.sets).toBeGreaterThanOrEqual(3);
      }

      // If leg_curl is included, it should have at least sets_min
      const legCurlBlock = plan.planned_blocks.find(b => b.exercise_id === 'leg_curl');
      if (legCurlBlock) {
        expect(legCurlBlock.sets).toBeGreaterThanOrEqual(2);
      }
    });

    test('prioritizes compounds over accessories', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'tricep_extension',
          muscle_groups: ['triceps'],
          priority: 1, // High priority but accessory
          sets_target: 3,
          sets_min: 2,
          reps: 15,
          rest_seconds: 60,
          category: 'accessory'
        },
        {
          id: 'deadlift',
          muscle_groups: ['back', 'glutes', 'hamstrings'],
          priority: 2, // Lower priority but compound
          sets_target: 3,
          sets_min: 2,
          reps: 5,
          rest_seconds: 180,
          category: 'compound'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 15, // Only room for one
        buffer_minutes: 2,
        warmup_policy: {
          include: true,
          max_minutes: 3
        }
      };

      const plan = fitToTimeBudget(candidates, config);

      // Should prefer compound despite lower priority number
      const exerciseIds = plan.planned_blocks.map(b => b.exercise_id);
      if (exerciseIds.length === 1) {
        expect(exerciseIds[0]).toBe('deadlift');
      }
    });
  });

  describe('validateTimeBudget', () => {
    test('validates plan within budget', () => {
      const plan = {
        total_planned_minutes: 58,
        planned_blocks: [],
        debug_plan: {
          budget_minutes: 60,
          buffer_minutes: 5,
          warmup_minutes: 5,
          cooldown_minutes: 0,
          transition_seconds_per_change: 25,
          sizing_steps: []
        }
      };

      const result = validateTimeBudget(plan, 60);
      expect(result.valid).toBe(true);
      expect(result.message).toBeUndefined();
    });

    test('rejects plan over budget', () => {
      const plan = {
        total_planned_minutes: 62,
        planned_blocks: [],
        debug_plan: {
          budget_minutes: 60,
          buffer_minutes: 5,
          warmup_minutes: 5,
          cooldown_minutes: 0,
          transition_seconds_per_change: 25,
          sizing_steps: []
        }
      };

      const result = validateTimeBudget(plan, 60);
      expect(result.valid).toBe(false);
      expect(result.message).toContain('exceeds budget');
    });

    test('warns when significantly under budget', () => {
      const plan = {
        total_planned_minutes: 40,
        planned_blocks: [],
        debug_plan: {
          budget_minutes: 60,
          buffer_minutes: 5,
          warmup_minutes: 5,
          cooldown_minutes: 0,
          transition_seconds_per_change: 25,
          sizing_steps: []
        }
      };

      const result = validateTimeBudget(plan, 60, 3);
      expect(result.valid).toBe(false);
      expect(result.message).toContain('under budget');
    });

    test('accepts plan within tolerance', () => {
      const plan = {
        total_planned_minutes: 57.5,
        planned_blocks: [],
        debug_plan: {
          budget_minutes: 60,
          buffer_minutes: 5,
          warmup_minutes: 5,
          cooldown_minutes: 0,
          transition_seconds_per_change: 25,
          sizing_steps: []
        }
      };

      const result = validateTimeBudget(plan, 60, 3);
      expect(result.valid).toBe(true);
    });
  });

  describe('createMinimalPlan', () => {
    test('creates minimal plan for 20 minute session', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'squat',
          muscle_groups: ['quads'],
          priority: 1,
          sets_target: 4,
          sets_min: 2,
          reps: 8,
          rest_seconds: 120,
          category: 'compound'
        },
        {
          id: 'bench_press',
          muscle_groups: ['chest'],
          priority: 2,
          sets_target: 4,
          sets_min: 2,
          reps: 8,
          rest_seconds: 120,
          category: 'compound'
        },
        {
          id: 'bicep_curl',
          muscle_groups: ['biceps'],
          priority: 3,
          sets_target: 3,
          sets_min: 2,
          reps: 12,
          rest_seconds: 60,
          category: 'isolation'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 20,
        buffer_minutes: 2
      };

      const plan = createMinimalPlan(candidates, config);

      // Should create a very minimal plan
      expect(plan.total_planned_minutes).toBeLessThanOrEqual(20);
      expect(plan.planned_blocks.length).toBeGreaterThan(0);
      expect(plan.planned_blocks.length).toBeLessThanOrEqual(2);

      // Should prefer compound
      const hasCompound = plan.planned_blocks.some(
        b => candidates.find(c => c.id === b.exercise_id)?.category === 'compound'
      );
      expect(hasCompound).toBe(true);

      // Should use minimum sets
      for (const block of plan.planned_blocks) {
        const candidate = candidates.find(c => c.id === block.exercise_id);
        expect(block.sets).toBe(candidate?.sets_min);
      }

      // Should have minimal warmup
      expect(plan.debug_plan.warmup_minutes).toBeLessThanOrEqual(3);
      
      // Should skip cooldown
      expect(plan.debug_plan.cooldown_minutes).toBe(0);
    });

    test('handles extremely limited time (15 minutes)', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'deadlift',
          muscle_groups: ['back', 'glutes'],
          priority: 1,
          sets_target: 5,
          sets_min: 2,
          reps: 5,
          rest_seconds: 180,
          category: 'compound'
        },
        {
          id: 'overhead_press',
          muscle_groups: ['delts'],
          priority: 2,
          sets_target: 4,
          sets_min: 2,
          reps: 8,
          rest_seconds: 120,
          category: 'compound'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 15
      };

      const plan = createMinimalPlan(candidates, config);

      // Should still create a valid minimal plan
      expect(plan.total_planned_minutes).toBeLessThanOrEqual(15);
      expect(plan.planned_blocks.length).toBeGreaterThanOrEqual(1);

      // Should include debug info explaining it's minimal
      const hasMinimalNote = plan.debug_plan.sizing_steps.some(
        step => step.toLowerCase().includes('minimal')
      );
      expect(hasMinimalNote).toBe(true);
    });

    test('skips accessory when time is too limited', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'squat',
          muscle_groups: ['quads'],
          priority: 1,
          sets_target: 3,
          sets_min: 2,
          reps: 5,
          rest_seconds: 150,
          category: 'compound'
        },
        {
          id: 'calf_raise',
          muscle_groups: ['calves'],
          priority: 2,
          sets_target: 4,
          sets_min: 3,
          reps: 20,
          rest_seconds: 45,
          category: 'accessory'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 10 // Extremely limited
      };

      const plan = createMinimalPlan(candidates, config);

      // Should only include the compound
      expect(plan.planned_blocks.length).toBe(1);
      expect(plan.planned_blocks[0].exercise_id).toBe('squat');
      expect(plan.planned_blocks[0].notes).toContain('Minimal');
    });
  });

  describe('Edge cases', () => {
    test('handles empty candidate list', () => {
      const candidates: ExerciseCandidate[] = [];
      const config: TimeConfig = {
        target_duration_minutes: 45
      };

      const plan = fitToTimeBudget(candidates, config);

      expect(plan.planned_blocks.length).toBe(0);
      expect(plan.total_planned_minutes).toBeLessThan(10); // Just warmup/cooldown if any
    });

    test('handles single exercise', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'bench_press',
          muscle_groups: ['chest'],
          priority: 1,
          sets_target: 3,
          sets_min: 2,
          reps: 10,
          rest_seconds: 90,
          category: 'compound'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 30
      };

      const plan = fitToTimeBudget(candidates, config);

      expect(plan.planned_blocks.length).toBe(1);
      expect(plan.planned_blocks[0].exercise_id).toBe('bench_press');
    });

    test('handles all exercises too long for budget', () => {
      const candidates: ExerciseCandidate[] = [
        {
          id: 'marathon_squats',
          muscle_groups: ['quads'],
          priority: 1,
          sets_target: 10,
          sets_min: 8,
          reps: 20,
          tempo_seconds_per_rep: 5,
          rest_seconds: 300,
          category: 'compound'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 10 // Too short for even minimal version
      };

      const plan = fitToTimeBudget(candidates, config);

      // Should either skip the exercise or create minimal plan
      if (plan.planned_blocks.length > 0) {
        // If included, should be trimmed to minimum
        expect(plan.planned_blocks[0].sets).toBe(8); // sets_min
      }
    });
  });
});
