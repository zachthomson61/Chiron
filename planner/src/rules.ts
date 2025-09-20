import type { Goal } from './types';

export const weeklySetsByGoal: Record<Goal, { primary: number; secondary: number }> = {
  strength:   { primary: 12, secondary: 6 },
  hypertrophy:{ primary: 14, secondary: 8 },
  endurance:  { primary: 10, secondary: 6 },
  recomp:     { primary: 12, secondary: 6 },
};

export const timePerExerciseMinutes = {
  compound: 8,
  isolation: 5,
} as const;




