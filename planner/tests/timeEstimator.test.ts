import { describe, test, expect } from 'vitest';
import {
  estimateWorkTime,
  estimateBlockMinutes,
  estimateSupersetMinutes,
  estimateCircuitMinutes,
  estimateWarmupMinutes,
  estimateCooldownMinutes,
  calculateTotalSessionMinutes,
  createTimeBreakdown,
  DEFAULT_CONFIG
} from '../src/timeEstimator';
import type { ExerciseCandidate, TimeConfig, PlannedBlock } from '../src/types';

describe('timeEstimator', () => {
  describe('estimateWorkTime', () => {
    test('calculates work time with tempo', () => {
      const exercise: ExerciseCandidate = {
        id: 'bench_press',
        muscle_groups: ['chest', 'triceps'],
        priority: 1,
        sets_target: 3,
        sets_min: 2,
        reps: 6,
        tempo_seconds_per_rep: 3,
        rest_seconds: 150,
        category: 'compound'
      };

      const workTime = estimateWorkTime(exercise, 'strength');
      expect(workTime).toBe(18); // 6 reps * 3 seconds
    });

    test('uses heuristics for compound exercises without tempo', () => {
      const exercise: ExerciseCandidate = {
        id: 'squat',
        muscle_groups: ['quads', 'glutes'],
        priority: 1,
        sets_target: 3,
        sets_min: 2,
        reps: 8,
        rest_seconds: 180,
        category: 'compound'
      };

      const workTimeStrength = estimateWorkTime(exercise, 'strength');
      expect(workTimeStrength).toBe(25); // strength heuristic

      const workTimeHypertrophy = estimateWorkTime(exercise, 'hypertrophy');
      expect(workTimeHypertrophy).toBe(60); // compound heuristic
    });

    test('uses heuristics for isolation exercises', () => {
      const exercise: ExerciseCandidate = {
        id: 'bicep_curl',
        muscle_groups: ['biceps'],
        priority: 3,
        sets_target: 3,
        sets_min: 2,
        reps: 12,
        rest_seconds: 60,
        category: 'isolation'
      };

      const workTime = estimateWorkTime(exercise);
      expect(workTime).toBe(40); // isolation heuristic
    });
  });

  describe('estimateBlockMinutes', () => {
    test('calculates compound set timing correctly', () => {
      const exercise: ExerciseCandidate = {
        id: 'bench_press',
        muscle_groups: ['chest', 'triceps'],
        priority: 1,
        sets_target: 3,
        sets_min: 2,
        reps: 6,
        tempo_seconds_per_rep: 3,
        rest_seconds: 150,
        category: 'compound'
      };

      const config: TimeConfig = {
        target_duration_minutes: 60,
        transition_seconds: 25
      };

      const minutes = estimateBlockMinutes(exercise, config, 'strength', true);
      
      // Calculation:
      // Work time: 3 sets * 6 reps * 3 sec = 54 sec
      // Rest time: 2 * 150 sec = 300 sec (no rest after last set)
      // Transition: 25 sec
      // Total: 54 + 300 + 25 = 379 sec = 6.32 minutes
      expect(minutes).toBeCloseTo(6.32, 1);
    });

    test('calculates accessory timing with heuristics', () => {
      const exercise: ExerciseCandidate = {
        id: 'lateral_raise',
        muscle_groups: ['delts'],
        priority: 4,
        sets_target: 2,
        sets_min: 1,
        reps: 15,
        rest_seconds: 60,
        category: 'accessory'
      };

      const config: TimeConfig = {
        target_duration_minutes: 45,
        transition_seconds: 25
      };

      const minutes = estimateBlockMinutes(exercise, config);
      
      // Calculation:
      // Work time: 2 sets * 35 sec (accessory heuristic) = 70 sec
      // Rest time: 1 * 60 sec = 60 sec
      // Transition: 25 sec
      // Total: 70 + 60 + 25 = 155 sec = 2.58 minutes
      expect(minutes).toBeCloseTo(2.58, 1);
    });

    test('handles rep ranges correctly', () => {
      const exercise: ExerciseCandidate = {
        id: 'squat',
        muscle_groups: ['quads', 'glutes'],
        priority: 1,
        sets_target: 3,
        sets_min: 2,
        reps: [8, 12], // rep range
        tempo_seconds_per_rep: 2,
        rest_seconds: 120,
        category: 'compound'
      };

      const config: TimeConfig = {
        target_duration_minutes: 60
      };

      const minutes = estimateBlockMinutes(exercise, config);
      
      // Should use max reps (12) for calculation
      // Work time: 3 sets * 12 reps * 2 sec = 72 sec
      // Rest time: 2 * 120 sec = 240 sec
      // Transition: 25 sec (default)
      // Total: 72 + 240 + 25 = 337 sec = 5.62 minutes
      expect(minutes).toBeCloseTo(5.62, 1);
    });

    test('excludes transition when requested', () => {
      const exercise: ExerciseCandidate = {
        id: 'bench_press',
        muscle_groups: ['chest'],
        priority: 1,
        sets_target: 2,
        sets_min: 1,
        reps: 10,
        tempo_seconds_per_rep: 2,
        rest_seconds: 90,
        category: 'compound'
      };

      const config: TimeConfig = {
        target_duration_minutes: 60,
        transition_seconds: 30
      };

      const withTransition = estimateBlockMinutes(exercise, config, 'hypertrophy', true);
      const withoutTransition = estimateBlockMinutes(exercise, config, 'hypertrophy', false);
      
      expect(withTransition - withoutTransition).toBeCloseTo(0.5, 1); // 30 sec = 0.5 min
    });
  });

  describe('estimateSupersetMinutes', () => {
    test('calculates superset timing correctly', () => {
      const exerciseA: ExerciseCandidate = {
        id: 'bench_press',
        muscle_groups: ['chest'],
        priority: 1,
        sets_target: 3,
        sets_min: 2,
        reps: 10,
        tempo_seconds_per_rep: 2,
        rest_seconds: 75,
        category: 'compound'
      };

      const exerciseB: ExerciseCandidate = {
        id: 'bent_row',
        muscle_groups: ['back'],
        priority: 1,
        sets_target: 3,
        sets_min: 2,
        reps: 10,
        tempo_seconds_per_rep: 2,
        rest_seconds: 75,
        category: 'compound'
      };

      const config: TimeConfig = {
        target_duration_minutes: 60,
        transition_seconds: 25
      };

      const minutes = estimateSupersetMinutes(exerciseA, exerciseB, config);
      
      // Calculation:
      // Work time A: 10 reps * 2 sec = 20 sec
      // Work time B: 10 reps * 2 sec = 20 sec
      // Combined work per set: 40 sec
      // Total work: 3 sets * 40 sec = 120 sec
      // Rest time: 2 * 75 sec = 150 sec (shared rest after pair)
      // Transition: 25 sec
      // Total: 120 + 150 + 25 = 295 sec = 4.92 minutes
      expect(minutes).toBeCloseTo(4.92, 1);
    });

    test('handles different set counts in superset', () => {
      const exerciseA: ExerciseCandidate = {
        id: 'dumbbell_curl',
        muscle_groups: ['biceps'],
        priority: 3,
        sets_target: 4,
        sets_min: 3,
        reps: 12,
        rest_seconds: 60,
        category: 'isolation'
      };

      const exerciseB: ExerciseCandidate = {
        id: 'tricep_extension',
        muscle_groups: ['triceps'],
        priority: 3,
        sets_target: 3,
        sets_min: 2,
        reps: 12,
        rest_seconds: 60,
        category: 'isolation'
      };

      const config: TimeConfig = {
        target_duration_minutes: 45
      };

      const minutes = estimateSupersetMinutes(exerciseA, exerciseB, config);
      
      // Should use max sets (4)
      expect(minutes).toBeGreaterThan(3);
      expect(minutes).toBeLessThan(8);
    });
  });

  describe('estimateCircuitMinutes', () => {
    test('calculates circuit timing correctly', () => {
      const exercises: ExerciseCandidate[] = [
        {
          id: 'pushup',
          muscle_groups: ['chest'],
          priority: 2,
          sets_target: 3,
          sets_min: 2,
          reps: 15,
          rest_seconds: 90,
          category: 'compound'
        },
        {
          id: 'squat',
          muscle_groups: ['quads'],
          priority: 2,
          sets_target: 3,
          sets_min: 2,
          reps: 15,
          rest_seconds: 90,
          category: 'compound'
        },
        {
          id: 'plank',
          muscle_groups: ['abs'],
          priority: 3,
          sets_target: 3,
          sets_min: 2,
          reps: 1,
          tempo_seconds_per_rep: 30,
          rest_seconds: 90,
          category: 'isolation'
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 45,
        default_rest_seconds: 90
      };

      const minutes = estimateCircuitMinutes(exercises, config, 'endurance', 3);
      
      // Work time per round: 60 + 60 + 30 = 150 sec
      // Total work: 3 rounds * 150 sec = 450 sec
      // Rest between rounds: 2 * 90 sec = 180 sec
      // Transition: 25 sec
      // Total: 450 + 180 + 25 = 655 sec = 10.92 minutes
      expect(minutes).toBeCloseTo(10.92, 1);
    });
  });

  describe('estimateWarmupMinutes', () => {
    test('respects warmup policy', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        warmup_policy: {
          include: true,
          max_minutes: 8
        }
      };

      const minutes = estimateWarmupMinutes(config, false);
      expect(minutes).toBe(5); // base minutes for non-heavy day
    });

    test('increases warmup for heavy days', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        warmup_policy: {
          include: true,
          max_minutes: 8
        }
      };

      const minutes = estimateWarmupMinutes(config, true);
      expect(minutes).toBe(6); // increased for heavy day
    });

    test('caps warmup at max minutes', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        warmup_policy: {
          include: true,
          max_minutes: 4
        }
      };

      const minutes = estimateWarmupMinutes(config, true);
      expect(minutes).toBe(4); // capped at max
    });

    test('returns 0 when warmup not included', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        warmup_policy: {
          include: false,
          max_minutes: 8
        }
      };

      const minutes = estimateWarmupMinutes(config);
      expect(minutes).toBe(0);
    });
  });

  describe('estimateCooldownMinutes', () => {
    test('respects cooldown policy', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        cooldown_policy: {
          include: true,
          minutes: 5
        }
      };

      const minutes = estimateCooldownMinutes(config);
      expect(minutes).toBe(5);
    });

    test('returns 0 when cooldown not included', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        cooldown_policy: {
          include: false,
          minutes: 5
        }
      };

      const minutes = estimateCooldownMinutes(config);
      expect(minutes).toBe(0);
    });

    test('uses default when minutes not specified', () => {
      const config: TimeConfig = {
        target_duration_minutes: 60,
        cooldown_policy: {
          include: true,
          minutes: undefined as any
        }
      };

      const minutes = estimateCooldownMinutes(config);
      expect(minutes).toBe(3); // default
    });
  });

  describe('calculateTotalSessionMinutes', () => {
    test('sums all components correctly', () => {
      const blocks: PlannedBlock[] = [
        {
          exercise_id: 'squat',
          sets: 3,
          reps: '8-10',
          rest_seconds: 150,
          estimated_minutes: 8.5
        },
        {
          exercise_id: 'bench_press',
          sets: 3,
          reps: 10,
          rest_seconds: 120,
          estimated_minutes: 7.2
        },
        {
          exercise_id: 'pullup',
          sets: 3,
          reps: '6-8',
          rest_seconds: 120,
          estimated_minutes: 6.8
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 60,
        buffer_minutes: 5,
        warmup_policy: {
          include: true,
          max_minutes: 8
        },
        cooldown_policy: {
          include: true,
          minutes: 3
        }
      };

      const total = calculateTotalSessionMinutes(blocks, config);
      
      // Expected:
      // Warmup: 5 min
      // Exercises: 8.5 + 7.2 + 6.8 = 22.5 min
      // Cooldown: 3 min
      // Buffer: 5 min
      // Total: 35.5 min
      expect(total).toBeCloseTo(35.5, 1);
    });
  });

  describe('createTimeBreakdown', () => {
    test('creates detailed breakdown', () => {
      const blocks: PlannedBlock[] = [
        {
          exercise_id: 'squat',
          sets: 3,
          reps: 10,
          rest_seconds: 150,
          estimated_minutes: 8
        },
        {
          exercise_id: 'deadlift',
          sets: 3,
          reps: 8,
          rest_seconds: 180,
          estimated_minutes: 9
        }
      ];

      const config: TimeConfig = {
        target_duration_minutes: 45,
        buffer_minutes: 4,
        transition_seconds: 30,
        warmup_policy: {
          include: true,
          max_minutes: 6
        },
        cooldown_policy: {
          include: true,
          minutes: 2
        }
      };

      const breakdown = createTimeBreakdown(blocks, config);
      
      expect(breakdown).toEqual({
        warmup_minutes: 5,
        exercise_minutes: 17,
        cooldown_minutes: 2,
        buffer_minutes: 4,
        total_minutes: 28,
        num_exercises: 2,
        transition_seconds: 30
      });
    });
  });
});
