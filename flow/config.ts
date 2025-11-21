// Flow configuration for one-question-at-a-time plan builder
export type Answer = string | number | boolean | string[];
export type StepId = string;

export interface Step {
  id: StepId;
  prompt: string;
  helper?: string;
  type: 'single' | 'multi' | 'number' | 'range' | 'chips' | 'yesno' | 'time' | 'text';
  options?: Array<{ value: string; label: string; helper?: string }>;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  validate?: (a: Answer) => string | null;
  next: (a: Answer, ctx: Record<string, Answer>) => StepId | 'RESULT';
  required?: boolean;
  placeholder?: string;
}

export interface FlowConfig {
  start: StepId;
  steps: Record<StepId, Step>;
  estimatedLength: number; // For progress calculation
}

export interface FlowState {
  current: StepId;
  answers: Record<StepId, Answer>;
  history: StepId[];
  startedAt: number;
  lastUpdatedAt: number;
}

// Main flow configuration
export const flow: FlowConfig = {
  start: 'plan_name',
  estimatedLength: 18,
  steps: {
    // 1. Plan Name
    plan_name: {
      id: 'plan_name',
      prompt: 'What would you like to name your training plan?',
      helper: 'Give your plan a memorable name that reflects your goals',
      type: 'text',
      placeholder: 'e.g., Summer Strength, Marathon Prep',
      required: true,
      validate: (a) => {
        const name = String(a).trim();
        if (name.length < 1) return 'Please enter a plan name (at least 1 character)';
        if (name.length > 50) return 'Name must be less than 50 characters';
        return null;
      },
      next: () => 'primary_goal'
    },

    // 2. Primary Goal
    primary_goal: {
      id: 'primary_goal',
      prompt: 'What is your primary training goal?',
      helper: 'This helps us tailor your program structure',
      type: 'single',
      options: [
        { value: 'muscle_gain', label: 'Build Muscle', helper: 'Focus on hypertrophy and size' },
        { value: 'strength', label: 'Get Stronger', helper: 'Increase max strength and power' },
        { value: 'fat_loss', label: 'Lose Fat', helper: 'Body recomposition and definition' },
        { value: 'endurance', label: 'Improve Endurance', helper: 'Build stamina and work capacity' },
        { value: 'athletic', label: 'Athletic Performance', helper: 'Sport-specific training' },
        { value: 'general', label: 'General Fitness', helper: 'Overall health and wellness' }
      ],
      required: true,
      next: (a) => {
        if (a === 'fat_loss' || a === 'endurance') return 'cardio_preference';
        if (a === 'athletic') return 'sport_type';
        return 'caloric_tracking';
      }
    },

    // 2a. Caloric Tracking
    caloric_tracking: {
      id: 'caloric_tracking',
      prompt: 'Do you currently track your calories or have a nutrition plan?',
      helper: 'This helps us align your training with your nutrition goals',
      type: 'single',
      options: [
        { value: 'yes_track', label: 'Yes, I track calories' },
        { value: 'no_healthy', label: 'No, but I eat generally healthy' },
        { value: 'no_improve', label: 'No, I\'d like to improve my nutrition' },
        { value: 'specific_plan', label: 'I have a specific diet plan' }
      ],
      required: true,
      next: (a) => {
        if (a === 'yes_track') return 'diet_phase';
        return 'experience_level';
      }
    },

    // 2b. Diet Phase (conditional)
    diet_phase: {
      id: 'diet_phase',
      prompt: 'What phase are you currently in?',
      helper: 'This helps us optimize your training volume and recovery needs',
      type: 'single',
      options: [
        { value: 'cutting', label: 'Cutting (calorie deficit)' },
        { value: 'bulking', label: 'Bulking (calorie surplus)' },
        { value: 'maintaining', label: 'Maintaining (maintenance calories)' },
        { value: 'not_consistent', label: 'Not consistently doing any of the above' }
      ],
      required: true,
      next: () => 'experience_level'
    },

    // 3. Cardio Preference (conditional)
    cardio_preference: {
      id: 'cardio_preference',
      prompt: 'How would you like to incorporate cardio?',
      helper: 'Cardio can complement your training goals',
      type: 'single',
      options: [
        { value: 'hiit', label: 'HIIT', helper: 'Short, intense intervals' },
        { value: 'steady', label: 'Steady State', helper: 'Moderate pace for longer duration' },
        { value: 'mixed', label: 'Mix of Both', helper: 'Variety of cardio styles' },
        { value: 'minimal', label: 'Minimal Cardio', helper: 'Focus mainly on weights' }
      ],
      required: true,
      next: () => 'caloric_tracking'
    },

    // 4. Sport Type (conditional)
    sport_type: {
      id: 'sport_type',
      prompt: 'What sport are you training for?',
      type: 'text',
      placeholder: 'e.g., Basketball, Soccer, CrossFit',
      required: true,
      validate: (a) => {
        const sport = String(a).trim();
        if (!sport) return 'Please enter a sport';
        return null;
      },
      next: () => 'caloric_tracking'
    },

    // 5. Experience Level
    experience_level: {
      id: 'experience_level',
      prompt: 'What is your training experience?',
      helper: 'This helps us set appropriate progressions',
      type: 'single',
      options: [
        { value: 'beginner', label: 'Beginner', helper: 'New to training (< 6 months)' },
        { value: 'novice', label: 'Novice', helper: '6-12 months of consistent training' },
        { value: 'intermediate', label: 'Intermediate', helper: '1-3 years experience' },
        { value: 'advanced', label: 'Advanced', helper: '3+ years of serious training' }
      ],
      required: true,
      next: () => 'current_activity_level'
    },

    // 5a. Current Activity Level
    current_activity_level: {
      id: 'current_activity_level',
      prompt: 'How many times per week are you currently exercising?',
      helper: 'This helps us understand your current training volume and avoid overdoing it',
      type: 'single',
      options: [
        { value: '0', label: '0 times per week (not currently exercising)' },
        { value: '1-2', label: '1-2 times per week' },
        { value: '3-4', label: '3-4 times per week' },
        { value: '5-6', label: '5-6 times per week' },
        { value: '7+', label: '7+ times per week (very active)' }
      ],
      required: true,
      next: () => 'days_per_week'
    },

    // 7. Days Per Week
    days_per_week: {
      id: 'days_per_week',
      prompt: 'How many days per week can you train?',
      helper: 'Be realistic about your schedule',
      type: 'range',
      min: 1,
      max: 7,
      step: 1,
      unit: 'days',
      required: true,
      validate: (a) => {
        const days = Number(a);
        if (days < 1) return 'Minimum 1 day per week';
        if (days > 7) return 'Maximum 7 days per week';
        return null;
      },
      next: (a) => {
        const days = Number(a);
        if (days <= 3) return 'time_limited_check';
        return 'session_duration';
      }
    },

    // 8. Time Limited Check (conditional)
    time_limited_check: {
      id: 'time_limited_check',
      prompt: 'Are you limited on training time?',
      helper: 'We\'ll prioritize the most effective exercises',
      type: 'yesno',
      required: true,
      next: (a) => {
        if (a === true) return 'session_duration_short';
        return 'session_duration';
      }
    },

    // 9. Session Duration
    session_duration: {
      id: 'session_duration',
      prompt: 'How long can you train per session?',
      type: 'range',
      min: 20,
      max: 120,
      step: 5,
      unit: 'minutes',
      required: true,
      next: () => 'target_muscles'
    },

    // 9b. Session Duration Short (conditional)
    session_duration_short: {
      id: 'session_duration_short',
      prompt: 'How many minutes per session?',
      helper: 'We\'ll design an efficient program',
      type: 'range',
      min: 15,
      max: 45,
      step: 5,
      unit: 'minutes',
      required: true,
      next: () => 'target_muscles'
    },

    // 10. Target Muscles
    target_muscles: {
      id: 'target_muscles',
      prompt: 'Which muscle groups do you want to focus on?',
      helper: 'Select all that apply (minimum 3)',
      type: 'multi',
      options: [
        { value: 'chest', label: '🫁 Chest' },
        { value: 'back', label: '🔙 Back' },
        { value: 'shoulders', label: '💪 Shoulders' },
        { value: 'arms', label: '💪 Arms' },
        { value: 'core', label: '🎯 Core' },
        { value: 'legs', label: '🦵 Legs' },
        { value: 'glutes', label: '🍑 Glutes' },
        { value: 'calves', label: '🦵 Calves' }
      ],
      required: true,
      validate: (a) => {
        const selected = a as string[];
        if (selected.length < 3) return 'Please select at least 3 muscle groups';
        return null;
      },
      next: () => 'specific_weaknesses'
    },

    // 10a. Specific Weaknesses
    specific_weaknesses: {
      id: 'specific_weaknesses',
      prompt: 'Are there any specific areas you feel are weak?',
      helper: 'This could be strength imbalances, mobility issues, or areas you struggle with',
      type: 'multi',
      options: [
        { value: 'upper_body_strength', label: 'Upper body strength' },
        { value: 'lower_body_strength', label: 'Lower body strength' },
        { value: 'core_stability', label: 'Core stability' },
        { value: 'mobility_flexibility', label: 'Mobility/Flexibility' },
        { value: 'cardiovascular_endurance', label: 'Cardiovascular endurance' },
        { value: 'balance_coordination', label: 'Balance/Coordination' },
        { value: 'posture', label: 'Posture' },
        { value: 'none', label: 'None - I feel balanced' },
        { value: 'custom', label: 'Other (specify)' }
      ],
      required: true,
      next: () => 'workout_split'
    },

    // 11. Workout Split
    workout_split: {
      id: 'workout_split',
      prompt: 'How would you like to organize your training?',
      type: 'single',
      options: [
        { value: 'full_body', label: 'Full Body', helper: 'Train all muscles each session' },
        { value: 'upper_lower', label: 'Upper/Lower', helper: 'Alternate upper and lower days' },
        { value: 'push_pull_legs', label: 'Push/Pull/Legs', helper: 'Classic 3-way split' },
        { value: 'body_part', label: 'Body Part Split', helper: 'Focus on 1-2 muscles per day' },
        { value: 'custom', label: 'Custom Split', helper: 'Design your own' }
      ],
      required: true,
      next: (a) => {
        if (a === 'custom') return 'custom_split_design';
        return 'equipment_available';
      }
    },

    // 12. Custom Split Design (conditional)
    custom_split_design: {
      id: 'custom_split_design',
      prompt: 'Describe your ideal workout split',
      helper: 'e.g., "Day 1: Chest/Tris, Day 2: Back/Bis, Day 3: Legs"',
      type: 'text',
      placeholder: 'Describe your split...',
      required: true,
      validate: (a) => {
        const text = String(a).trim();
        if (!text || text.length < 10) return 'Please provide more detail';
        return null;
      },
      next: () => 'equipment_available'
    },

    // 13. Equipment Available
    equipment_available: {
      id: 'equipment_available',
      prompt: 'What equipment do you have access to?',
      type: 'multi',
      options: [
        { value: 'barbell', label: '🏋️ Barbell' },
        { value: 'dumbbells', label: '🏋️ Dumbbells' },
        { value: 'cables', label: '🔗 Cable Machine' },
        { value: 'machines', label: '⚙️ Gym Machines' },
        { value: 'kettlebells', label: '🔔 Kettlebells' },
        { value: 'bands', label: '🎗️ Resistance Bands' },
        { value: 'bodyweight', label: '🤸 Bodyweight Only' },
        { value: 'pullup_bar', label: '🚪 Pull-up Bar' }
      ],
      required: true,
      validate: (a) => {
        const selected = a as string[];
        if (selected.length === 0) return 'Please select at least one option';
        return null;
      },
      next: () => 'training_preferences_lifting'
    },

    // 13a. Training Preferences - Lifting Style
    training_preferences_lifting: {
      id: 'training_preferences_lifting',
      prompt: 'What kinds of movements do you enjoy most?',
      helper: 'This helps us select exercises that match your preferences',
      type: 'multi',
      options: [
        { value: 'compound', label: 'Big compound movements (squats, deadlifts, presses)' },
        { value: 'isolation', label: 'Isolation work (targeting specific muscles)' },
        { value: 'unilateral', label: 'Unilateral movements (one side at a time)' },
        { value: 'explosive', label: 'Explosive/power movements (jumps, throws)' },
        { value: 'controlled', label: 'Controlled, slow movements (time under tension)' },
        { value: 'bodyweight', label: 'Bodyweight movements' },
        { value: 'mix', label: 'Mix of everything' },
        { value: 'open', label: 'I\'m open to trying new things' }
      ],
      required: true,
      validate: (a) => {
        const selected = a as string[];
        if (selected.length === 0) return 'Please select at least one option';
        return null;
      },
      next: () => 'training_preferences_cardio'
    },

    // 13b. Training Preferences - Cardio Style
    training_preferences_cardio: {
      id: 'training_preferences_cardio',
      prompt: 'What\'s your preference for cardio training?',
      helper: 'This helps us structure cardio sessions that you\'ll actually enjoy and stick with',
      type: 'single',
      options: [
        { value: 'love', label: 'I love cardio (bring it on!)' },
        { value: 'enjoy', label: 'I enjoy some cardio (moderate amounts)' },
        { value: 'tolerate', label: 'I tolerate cardio (keep it minimal)' },
        { value: 'dislike', label: 'I really dislike cardio (avoid it if possible)' },
        { value: 'specific_types', label: 'I prefer specific types' }
      ],
      required: true,
      next: (a) => {
        if (a === 'specific_types') return 'cardio_type_preference';
        return 'training_intensity'
      }
    },

    // 13c. Cardio Type Preference (conditional)
    cardio_type_preference: {
      id: 'cardio_type_preference',
      prompt: 'Which types of cardio do you enjoy?',
      helper: 'Select all that apply',
      type: 'multi',
      options: [
        { value: 'running', label: 'Running/Jogging' },
        { value: 'cycling', label: 'Cycling/Spinning' },
        { value: 'swimming', label: 'Swimming' },
        { value: 'rowing', label: 'Rowing' },
        { value: 'elliptical', label: 'Elliptical/Stair Climber' },
        { value: 'hiit', label: 'HIIT/Intervals' },
        { value: 'steady_state', label: 'Steady State' },
        { value: 'walking', label: 'Walking' },
        { value: 'dance', label: 'Dance/Zumba' },
        { value: 'other', label: 'Other' }
      ],
      required: true,
      validate: (a) => {
        const selected = a as string[];
        if (selected.length === 0) return 'Please select at least one type';
        return null;
      },
      next: () => 'training_intensity'
    },

    // 13d. Training Intensity Preference
    training_intensity: {
      id: 'training_intensity',
      prompt: 'How intense do you like your workouts to feel?',
      helper: 'This helps us set appropriate rest times and volume',
      type: 'single',
      options: [
        { value: 'light', label: 'Light and easy (I prefer steady pace)' },
        { value: 'moderate', label: 'Moderate (challenging but sustainable)' },
        { value: 'high', label: 'High intensity (I like to push hard)' },
        { value: 'varied', label: 'Varied (mix of intensities)' }
      ],
      required: true,
      next: () => 'injury_check'
    },

    // 14. Injury Check
    injury_check: {
      id: 'injury_check',
      prompt: 'Do you have any injuries or physical limitations?',
      type: 'yesno',
      required: true,
      next: (a) => {
        if (a === true) return 'injury_details';
        return 'exercise_variety';
      }
    },

    // 15. Injury Details (conditional)
    injury_details: {
      id: 'injury_details',
      prompt: 'Describe your injuries or limitations',
      helper: 'We\'ll avoid exercises that could aggravate these areas',
      type: 'text',
      placeholder: 'e.g., Lower back pain, shoulder impingement',
      required: true,
      next: () => 'exercise_variety'
    },

    // 16. Exercise Variety
    exercise_variety: {
      id: 'exercise_variety',
      prompt: 'How much exercise variety do you prefer?',
      helper: 'Some prefer consistency, others like frequent changes',
      type: 'single',
      options: [
        { value: 'consistent', label: 'Consistent', helper: 'Same exercises each week' },
        { value: 'balanced', label: 'Balanced', helper: 'Some variety, core stays same' },
        { value: 'varied', label: 'Highly Varied', helper: 'Frequent exercise changes' }
      ],
      required: true,
      next: () => 'supersets'
    },

    // 17. Supersets
    supersets: {
      id: 'supersets',
      prompt: 'Would you like to include supersets?',
      helper: 'Pair exercises to save time and increase intensity',
      type: 'yesno',
      required: true,
      next: () => 'program_duration'
    },

    // 18. Program Duration
    program_duration: {
      id: 'program_duration',
      prompt: 'How long should this program last?',
      type: 'range',
      min: 4,
      max: 24,
      step: 2,
      unit: 'weeks',
      required: true,
      next: () => 'start_date'
    },

    // 19. Start Date
    start_date: {
      id: 'start_date',
      prompt: 'When would you like to start?',
      type: 'single',
      options: [
        { value: 'today', label: 'Today' },
        { value: 'tomorrow', label: 'Tomorrow' },
        { value: 'next_monday', label: 'Next Monday' },
        { value: 'custom', label: 'Pick a Date' }
      ],
      required: true,
      next: (a) => {
        if (a === 'custom') return 'custom_start_date';
        return 'RESULT';
      }
    },

    // 20. Custom Start Date (conditional)
    custom_start_date: {
      id: 'custom_start_date',
      prompt: 'Select your start date',
      type: 'text', // In implementation, this would be a date picker
      placeholder: 'YYYY-MM-DD',
      required: true,
      validate: (a) => {
        const dateStr = String(a).trim();
        const date = new Date(dateStr);
        if (isNaN(date.getTime())) return 'Please enter a valid date';
        if (date < new Date(new Date().setHours(0,0,0,0))) return 'Date cannot be in the past';
        return null;
      },
      next: () => 'RESULT'
    }
  }
};

// Helper function to calculate estimated path length for a given context
export function calculatePathLength(answers: Record<string, Answer>): number {
  let length = 0;
  let currentStep = flow.start;
  const visited = new Set<string>();
  
  while (currentStep !== 'RESULT' && !visited.has(currentStep)) {
    visited.add(currentStep);
    length++;
    
    const step = flow.steps[currentStep];
    if (!step) break;
    
    // Use actual answer if available, otherwise assume default path
    const answer = answers[currentStep];
    if (answer !== undefined) {
      currentStep = step.next(answer, answers);
    } else {
      // Assume default path (first option or false for yes/no)
      const defaultAnswer = step.type === 'yesno' ? false : 
                           step.options?.[0]?.value || '';
      currentStep = step.next(defaultAnswer, answers);
    }
    
    // Prevent infinite loops
    if (length > 30) break;
  }
  
  return length;
}


