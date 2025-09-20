import type { ProgramPlan, Exercise } from './types';

export function rationaleForExercise(ex: Exercise): string {
  const parts: string[] = [];
  if (ex.primaryMuscles.length) parts.push(`Targets ${ex.primaryMuscles.join(', ')}`);
  if (ex.flags.includes('time_efficient')) parts.push('Time-efficient');
  if (ex.flags.includes('knee_friendly')) parts.push('Knee-friendly');
  if (ex.flags.includes('shoulder_friendly')) parts.push('Shoulder-friendly');
  if (ex.flags.includes('spine_friendly')) parts.push('Spine-friendly');
  return parts.join(' • ');
}

export function explain(plan: ProgramPlan): string {
  return `Goal: ${plan.meta.goal}. Split: ${plan.meta.split}. Days/week: ${plan.meta.schedule.daysPerWeek}. Variety: ${plan.meta.variety}. Supersets: ${plan.meta.supersets ? 'on' : 'off'}.`;
}



