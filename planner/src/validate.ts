import type { Goal, Inputs } from './types';

const minutesPerPrimarySet: Record<Goal, number> = {
  strength: 8,
  hypertrophy: 6,
  endurance: 5,
  recomp: 6,
};

export function requiredMinutes(goal: Goal, targetMuscles: Inputs['targetMuscles']): number {
  const base = minutesPerPrimarySet[goal] * Math.max(3, targetMuscles.length);
  return base + 10; // warmup/cooldown allowance
}

export function validateInputs(input: Inputs): string[] {
  const warnings: string[] = [];
  const totalCapacity = input.schedule.daysPerWeek * input.schedule.sessionMinutes;
  if (totalCapacity < requiredMinutes(input.goal, input.targetMuscles)) {
    warnings.push('Schedule may be too tight for requested goal/muscles. Consider enabling supersets or reducing variety.');
  }
  // injuries corner cases
  const tags = input.injuries.map(i=>i.tag);
  if (input.goal === 'strength' && (tags.includes('knee') || tags.includes('low_back'))) {
    warnings.push('Strength goal with knee/low back issues: plan will favor friendly variations.');
  }
  return warnings;
}


