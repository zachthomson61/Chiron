export type Goal = 'hypertrophy' | 'strength' | 'endurance' | 'recomp';

export type Split =
  | 'FB-3'
  | 'UL-4'
  | 'PPL-6'
  | 'ULUL-4'
  | 'UPPER-3'
  | 'LOWER-3';

export interface Schedule {
  daysPerWeek: 2 | 3 | 4 | 5 | 6;
  sessionMinutes: 30 | 45 | 60 | 75 | 90;
  programWeeks: number; // 4–16
}

export interface InjuryConstraint {
  tag: 'knee'|'shoulder'|'elbow'|'low_back'|'hip'|'ankle'|'wrist'|'neck';
  severity: 'avoid'|'modify';
}

export type Variety = 'consistent'|'balanced'|'varied';

export interface Inputs {
  goal: Goal;
  schedule: Schedule;
  targetMuscles: Array<'chest'|'back'|'delts'|'biceps'|'triceps'|'quads'|'hams'|'glutes'|'calves'|'abs'|'low_back'|'adductors'|'abductors'|'forearms'|'traps'>;
  split: Split;
  injuries: InjuryConstraint[];
  variety: Variety;
  supersets: boolean;
}

export interface Exercise {
  id: string;
  name: string;
  primaryMuscles: string[];
  secondaryMuscles: string[];
  pattern: 'squat'|'hinge'|'lunge'|'push_h'|'push_v'|'pull_h'|'pull_v'|'carry'|'isolation';
  equipment: ('db'|'bb'|'machine'|'cable'|'bodyweight')[];
  flags: ('knee_friendly'|'shoulder_friendly'|'spine_friendly'|'unilateral'|'bilateral'|'time_efficient')[];
}

export interface SessionSlot {
  muscles: string[];
  slots: number;
  minutesBudget: number;
}

export interface TemplateDay { dayIndex: number; slotPlan: SessionSlot[]; }
export interface MicrocycleTemplate { split: Split; days: TemplateDay[]; }

export interface SetScheme { sets: number; reps: [number,number]; rpeCap: number; restSec: number; }
export interface ExerciseSelection { exerciseId: string; scheme: SetScheme; supersetWith?: string; }

export interface DayPlan { dayIndex: number; items: ExerciseSelection[]; estMinutes: number; }
export interface WeekPlan { weekIndex: number; days: DayPlan[]; deload?: boolean; }
export interface ProgramPlan { meta: Inputs; weeks: WeekPlan[]; }

export interface DebugEvent { step: string; detail: Record<string, unknown>; }
export type DebugLog = DebugEvent[];


