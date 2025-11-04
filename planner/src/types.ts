export type Goal = 'hypertrophy' | 'strength' | 'endurance' | 'recomp' | 'fat_loss';

export type Split =
  | 'FB-3'
  | 'UL-4'
  | 'PPL-6'
  | 'ULUL-4'
  | 'UPPER-3'
  | 'LOWER-3'
  | 'upper'
  | 'lower'
  | 'full_body';

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

export interface WarmupPolicy {
  include: boolean;
  max_minutes: number;
}

export interface CooldownPolicy {
  include: boolean;
  minutes: number;
}

export interface ExerciseCandidate {
  id: string;
  muscle_groups: string[];
  priority: number;
  sets_target: number;
  sets_min: number;
  reps: number | [number, number];
  tempo_seconds_per_rep?: number;
  rest_seconds: number;
  superset_with?: string;
  category: 'compound' | 'isolation' | 'accessory';
  pattern?: 'squat'|'hinge'|'lunge'|'push_h'|'push_v'|'pull_h'|'pull_v'|'carry'|'isolation';
}

export interface TimeConfig {
  target_duration_minutes: number;
  buffer_minutes?: number;
  transition_seconds?: number;
  min_rest_accessory?: number;
  warmup_max_minutes?: number;
  default_rest_seconds?: number;
}

export interface Inputs {
  goal: Goal;
  schedule: Schedule;
  targetMuscles: Array<'chest'|'back'|'delts'|'biceps'|'triceps'|'quads'|'hams'|'glutes'|'calves'|'abs'|'low_back'|'adductors'|'abductors'|'forearms'|'traps'>;
  split: Split;
  injuries: InjuryConstraint[];
  variety: Variety;
  supersets: boolean;
  // New time-bounded fields
  target_duration_minutes?: number;
  allow_supersets?: boolean;
  default_rest_seconds?: number;
  transition_seconds?: number;
  warmup_policy?: WarmupPolicy;
  cooldown_policy?: CooldownPolicy;
  exercise_pool?: ExerciseCandidate[];
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
export interface ExerciseSelection { exerciseId: string; scheme: SetScheme; supersetWith?: string; estimated_minutes?: number; }

export interface PlannedBlock {
  exercise_id: string;
  sets: number;
  reps: number | string;
  rest_seconds: number;
  estimated_minutes: number;
  notes?: string;
  superset_with?: string;
}

export interface DebugPlan {
  budget_minutes: number;
  buffer_minutes: number;
  warmup_minutes: number;
  cooldown_minutes: number;
  transition_seconds_per_change: number;
  sizing_steps: string[];
}

export interface TimeBoundedPlan {
  total_planned_minutes: number;
  planned_blocks: PlannedBlock[];
  debug_plan: DebugPlan;
}

export interface DayPlan { 
  dayIndex: number; 
  items: ExerciseSelection[]; 
  estMinutes: number;
  timeBoundedPlan?: TimeBoundedPlan;
}
export interface WeekPlan { weekIndex: number; days: DayPlan[]; deload?: boolean; }
export interface ProgramPlan { meta: Inputs; weeks: WeekPlan[]; }

export interface DebugEvent { step: string; detail: Record<string, unknown>; }
export type DebugLog = DebugEvent[];




