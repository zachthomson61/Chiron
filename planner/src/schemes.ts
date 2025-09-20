import type { Goal, SetScheme } from './types';

export function schemeFor(goal: Goal): SetScheme {
  switch (goal) {
    case 'strength':   return { sets: 4, reps: [3,6],  rpeCap: 9, restSec: 180 };
    case 'hypertrophy':return { sets: 3, reps: [8,12], rpeCap: 8, restSec: 90  };
    case 'endurance':  return { sets: 3, reps: [12,20],rpeCap: 7, restSec: 60  };
    case 'recomp':     return { sets: 3, reps: [6,12], rpeCap: 8, restSec: 90  };
  }
}


