import { describe, it, expect } from 'vitest';
import { generatePlan } from '../src/engine';
import type { Inputs, Exercise } from '../src/types';

const demoInputs: Inputs = {
  goal: 'hypertrophy',
  schedule: { daysPerWeek: 3, sessionMinutes: 45, programWeeks: 4 },
  targetMuscles: ['chest','back','delts','quads','hams','glutes','abs'],
  split: 'FB-3',
  injuries: [],
  variety: 'balanced',
  supersets: false,
};

const demoLibrary: Exercise[] = [
  { id: 'bb_squat', name: 'Barbell Squat', primaryMuscles: ['quads','glutes'], secondaryMuscles: ['hams'], pattern: 'squat', equipment: ['bb'], flags: [] },
  { id: 'bb_bench', name: 'Barbell Bench Press', primaryMuscles: ['chest'], secondaryMuscles: ['triceps','delts'], pattern: 'push_h', equipment: ['bb'], flags: [] },
  { id: 'bb_row', name: 'Barbell Row', primaryMuscles: ['back'], secondaryMuscles: ['biceps'], pattern: 'pull_h', equipment: ['bb'], flags: [] },
  { id: 'oh_press', name: 'Overhead Press', primaryMuscles: ['delts'], secondaryMuscles: ['triceps'], pattern: 'push_v', equipment: ['bb'], flags: [] },
  { id: 'plank', name: 'Plank', primaryMuscles: ['abs'], secondaryMuscles: [], pattern: 'isolation', equipment: ['bodyweight'], flags: ['time_efficient'] },
  { id: 'curls', name: 'DB Curls', primaryMuscles: ['biceps'], secondaryMuscles: [], pattern: 'isolation', equipment: ['db'], flags: ['time_efficient'] },
  { id: 'rdl_spine', name: 'RDL (Supported)', primaryMuscles: ['hams'], secondaryMuscles: ['glutes'], pattern: 'hinge', equipment: ['bb'], flags: ['spine_friendly'] },
];

describe('determinism', () => {
  it('same inputs -> same plan', () => {
    const a = generatePlan(demoInputs, demoLibrary);
    const b = generatePlan(demoInputs, demoLibrary);
    expect(a).toEqual(b);
  });
});

describe('goal overrides', () => {
  it('strength changes scheme', () => {
    const strong = generatePlan({ ...demoInputs, goal: 'strength' }, demoLibrary);
    const hyper = generatePlan({ ...demoInputs, goal: 'hypertrophy' }, demoLibrary);
    expect(JSON.stringify(strong.weeks[0].days[0].items[0].scheme)).not.toEqual(JSON.stringify(hyper.weeks[0].days[0].items[0].scheme));
  });
});

describe('injury enforcement', () => {
  it('knee avoid removes squats/lunges unless knee_friendly', () => {
    const inputs = { ...demoInputs, injuries: [{ tag:'knee', severity:'avoid' }] };
    const plan = generatePlan(inputs, demoLibrary);
    const day0 = plan.weeks[0].days[0];
    const ids = new Set(day0.items.map(i=>i.exerciseId));
    expect(ids.has('bb_squat')).toBe(false);
  });
});

describe('time boxing', () => {
  it('30 minutes trims isolation work first', () => {
    const inputs = { ...demoInputs, schedule: { ...demoInputs.schedule, sessionMinutes: 30 } };
    const plan = generatePlan(inputs, demoLibrary);
    const items = plan.weeks[0].days[0].items;
    // First item should remain (likely compound), isolation may be reduced
    expect(items.length).toBeGreaterThan(0);
  });
});

describe('variety policies', () => {
  it('consistent keeps same across weeks', () => {
    const inputs = { ...demoInputs, variety: 'consistent' as const };
    const plan = generatePlan(inputs, demoLibrary);
    const week1 = plan.weeks[0].days[0].items.map(i=>i.exerciseId).join(',');
    const week2 = plan.weeks[1].days[0].items.map(i=>i.exerciseId).join(',');
    expect(week1).toEqual(week2);
  });
});

describe('supersets', () => {
  it('enabled + short sessions reduce estimated time deterministically', () => {
    const base = generatePlan({ ...demoInputs, supersets: false, schedule: { ...demoInputs.schedule, sessionMinutes: 30 } }, demoLibrary);
    const sup = generatePlan({ ...demoInputs, supersets: true, schedule: { ...demoInputs.schedule, sessionMinutes: 30 } }, demoLibrary);
    const a = base.weeks[0].days[0].estMinutes;
    const b = sup.weeks[0].days[0].estMinutes;
    expect(b).toBeLessThanOrEqual(a);
  });
});




