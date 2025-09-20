import type { Inputs, ProgramPlan, Exercise, ExerciseSelection, WeekPlan, DayPlan } from './types';
import { TEMPLATES } from './templates';
import { weeklySetsByGoal, timePerExerciseMinutes } from './rules';
import { schemeFor } from './schemes';
import { isAllowed, modifiedSchemePenalty } from './injuries';

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

  // 3) Weekly volume targets
  const volTarget = weeklySetsByGoal[input.goal];
  const targets = input.targetMuscles.length > 0 ? input.targetMuscles : ['chest','back','delts','quads','hams','glutes','calves','abs'] as Inputs['targetMuscles'];

  const weeks: WeekPlan[] = [];
  for (let w = 0; w < schedule.programWeeks; w++) {
    const days: DayPlan[] = [];
    for (const day of template.days) {
      // 4) Select exercises per day
      const allowed = library.filter(ex => isAllowed(ex, input.injuries));

      const scored = allowed.map(ex => {
        const primaryMatch = ex.primaryMuscles.some(m => targets.includes(m as any)) ? 1 : 0;
        const secondaryMatch = ex.secondaryMuscles.some(m => targets.includes(m as any)) ? 1 : 0;
        const timeEfficiency = ex.flags.includes('time_efficient') ? 1 : 0;
        const patternCoverage = new Set(ex.primaryMuscles.concat(ex.secondaryMuscles)).size > 1 ? 1 : 0;
        const equipmentAvailability = ex.equipment.length > 0 ? 1 : 0;
        const score = 3*primaryMatch + 2*patternCoverage + 1*timeEfficiency + 1*equipmentAvailability + 0.5*secondaryMatch;
        return { ex, score };
      });

      const sorted = stableSort(scored, (a,b)=>{
        if (b.score !== a.score) return b.score - a.score;
        return a.ex.id.localeCompare(b.ex.id);
      }).map(s => s.ex);

      // take top K per first slot definition
      const firstSlot = day.slotPlan[0];
      let chosen = sorted.slice(0, firstSlot.slots);

      // 5) Enforce sessionMinutes by trimming isolation first
      const estimateMinutes = (items: Exercise[]) => {
        return items.reduce((sum, e) => sum + (e.pattern === 'isolation' ? timePerExerciseMinutes.isolation : timePerExerciseMinutes.compound), 0);
      };
      while (estimateMinutes(chosen) > schedule.sessionMinutes) {
        const idx = chosen.findLastIndex(e => e.pattern === 'isolation');
        if (idx >= 0) chosen.splice(idx,1); else break;
      }

      // 6) Variety handling
      // consistent: keep chosen as-is across weeks; balanced/varied: deterministic rotate
      if (input.variety !== 'consistent' && chosen.length > 0) {
        const offset = input.variety === 'balanced' ? (w % chosen.length) : ((w) % chosen.length);
        chosen = chosen.map((_, i) => chosen[(i + offset) % chosen.length]);
      }

      // 7) Deload weeks 4,8,12 reduce sets by 30%
      const isDeload = [3,7,11].includes(w); // zero-indexed weeks 4,8,12
      const items: ExerciseSelection[] = [];
      for (let i = 0; i < chosen.length; i++) {
        const e = chosen[i];
        const pen = modifiedSchemePenalty(e.pattern, input.injuries);
        const sets = Math.max(1, Math.round(scheme.sets - pen - (isDeload ? scheme.sets*0.3 : 0)));
        items.push({
          exerciseId: e.id,
          scheme: { ...scheme, sets },
        });
      }

      // Supersets deterministic optional pairing for short sessions
      if (input.supersets && schedule.sessionMinutes < 45) {
        for (let i = 0; i + 1 < items.length; i += 2) {
          items[i].supersetWith = items[i+1].exerciseId;
        }
      }

      const estMinutes = estimateMinutes(chosen);
      days.push({ dayIndex: day.dayIndex, items, estMinutes });
    }
    weeks.push({ weekIndex: w+1, days, deload: [4,8,12].includes(w+1) });
  }

  return { meta: input, weeks };
}




