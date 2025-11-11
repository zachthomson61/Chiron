// Plan generator utility - creates workout plans from user answers
import { OpenAI } from 'openai';

export interface PlanConfig {
  name: string;
  primaryGoal: string;
  experience: string;
  daysPerWeek: number;
  sessionMinutes: number;
  targetMuscles: string[];
  workoutSplit: string;
  customSplit?: string;
  equipment: string[];
  injuries?: string;
  exerciseVariety: string;
  includeSupersets: boolean;
  programDuration: number;
  startDate: Date;
  cardioPreference?: string;
  sport?: string;
  includeTutorials: boolean;
  // New personalization fields
  currentActivityLevel?: string;
  caloricTracking?: string;
  dietPhase?: string;
  specificWeaknesses?: string[];
  trainingPreferencesLifting?: string[];
  trainingPreferencesCardio?: string;
  cardioTypePreference?: string[];
  trainingIntensity?: string;
}

export interface Exercise {
  name: string;
  sets: number;
  reps: string;
  rest: string;
  notes?: string;
  videoUrl?: string;
}

export interface Workout {
  day: string;
  name: string;
  focus: string[];
  exercises: Exercise[];
  duration: number;
  warmup?: string[];
  cooldown?: string[];
}

export interface GeneratedPlan {
  name: string;
  description: string;
  workouts: Workout[];
  schedule: {
    daysPerWeek: number;
    sessionMinutes: number;
    programWeeks: number;
  };
  progressionNotes: string;
  equipmentNeeded: string[];
}

// Initialize OpenAI client (you can replace this with your preferred AI service)
const openai = process.env.OPENAI_API_KEY ? new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
}) : null;

// Generate a workout plan from user answers
export async function generatePlanFromAnswers(config: PlanConfig): Promise<GeneratedPlan> {
  // Try AI generation first, fall back to algorithmic if unavailable
  if (openai && process.env.OPENAI_API_KEY) {
    try {
      return await generatePlanWithAI(config);
    } catch (error) {
      console.error('AI generation failed, falling back to algorithmic:', error);
      return generatePlanAlgorithmically(config);
    }
  }
  
  return generatePlanAlgorithmically(config);
}

// AI-powered plan generation
async function generatePlanWithAI(config: PlanConfig): Promise<GeneratedPlan> {
  if (!openai) {
    throw new Error('OpenAI client not initialized');
  }

  const prompt = createAIPrompt(config);
  
  const completion = await openai.chat.completions.create({
    model: 'gpt-4',
    messages: [
      {
        role: 'system',
        content: 'You are an expert personal trainer and exercise physiologist. Create detailed, science-based workout plans that are safe and effective.'
      },
      {
        role: 'user',
        content: prompt
      }
    ],
    temperature: 0.7,
    max_tokens: 2000
  });

  const response = completion.choices[0]?.message?.content;
  if (!response) {
    throw new Error('No response from AI');
  }

  // Parse the AI response into our structure
  return parseAIResponse(response, config);
}

// Create prompt for AI
function createAIPrompt(config: PlanConfig): string {
  // Build personalization context
  let personalizationContext = '';
  if (config.currentActivityLevel) {
    personalizationContext += `\nCurrent Activity Level: ${config.currentActivityLevel} (adjust volume to avoid overload if already training frequently)`;
  }
  if (config.caloricTracking && config.dietPhase) {
    personalizationContext += `\nDiet Phase: ${config.dietPhase} (cutting: lower volume, preserve strength; bulking: higher volume; maintaining: balanced)`;
  }
  if (config.specificWeaknesses && config.specificWeaknesses.length > 0) {
    personalizationContext += `\nSpecific Weaknesses to Address: ${config.specificWeaknesses.join(', ')} (prioritize exercises targeting these areas)`;
  }
  if (config.trainingPreferencesLifting && config.trainingPreferencesLifting.length > 0) {
    personalizationContext += `\nLifting Preferences: ${config.trainingPreferencesLifting.join(', ')} (select exercises matching these movement types)`;
  }
  if (config.trainingPreferencesCardio) {
    personalizationContext += `\nCardio Preference: ${config.trainingPreferencesCardio} (adjust cardio volume accordingly)`;
    if (config.cardioTypePreference && config.cardioTypePreference.length > 0) {
      personalizationContext += `\nPreferred Cardio Types: ${config.cardioTypePreference.join(', ')}`;
    }
  }
  if (config.trainingIntensity) {
    personalizationContext += `\nTraining Intensity Preference: ${config.trainingIntensity} (light: +30% rest time; moderate: base; high: -10% rest time; varied: mix)`;
  }
  
  return `Create a ${config.programDuration}-week training program with the following requirements:

Name: ${config.name}
Primary Goal: ${config.primaryGoal}
Experience Level: ${config.experience}${personalizationContext}
Training Days: ${config.daysPerWeek} days per week
Session Duration: ${config.sessionMinutes} minutes
Target Muscles: ${config.targetMuscles.join(', ')}
Workout Split: ${config.workoutSplit}${config.customSplit ? ` (${config.customSplit})` : ''}
Available Equipment: ${config.equipment.join(', ')}
${config.injuries ? `Injuries/Limitations: ${config.injuries}` : ''}
Exercise Variety: ${config.exerciseVariety}
Include Supersets: ${config.includeSupersets ? 'Yes' : 'No'}
${config.cardioPreference ? `Cardio Preference: ${config.cardioPreference}` : ''}
${config.sport ? `Sport: ${config.sport}` : ''}

Please provide:
1. A weekly workout schedule
2. Detailed exercises for each workout (sets, reps, rest)
3. Progression recommendations
4. Any necessary equipment list

Format the response as JSON with this structure:
{
  "workouts": [
    {
      "day": "Day 1",
      "name": "Workout Name",
      "focus": ["muscle groups"],
      "exercises": [
        {
          "name": "Exercise Name",
          "sets": 3,
          "reps": "8-10",
          "rest": "90s",
          "notes": "form cues"
        }
      ]
    }
  ],
  "progressionNotes": "How to progress",
  "equipmentNeeded": ["equipment list"]
}`;
}

// Parse AI response
function parseAIResponse(response: string, config: PlanConfig): GeneratedPlan {
  try {
    // Try to extract JSON from the response
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return {
        name: config.name,
        description: `A ${config.programDuration}-week ${config.primaryGoal} program`,
        workouts: parsed.workouts || [],
        schedule: {
          daysPerWeek: config.daysPerWeek,
          sessionMinutes: config.sessionMinutes,
          programWeeks: config.programDuration
        },
        progressionNotes: parsed.progressionNotes || '',
        equipmentNeeded: parsed.equipmentNeeded || config.equipment
      };
    }
  } catch (error) {
    console.error('Failed to parse AI response:', error);
  }
  
  // Fall back to algorithmic generation if parsing fails
  return generatePlanAlgorithmically(config);
}

// Algorithmic plan generation (fallback)
export function generatePlanAlgorithmically(config: PlanConfig): GeneratedPlan {
  const workouts: Workout[] = [];
  
  // Generate workouts based on split type
  switch (config.workoutSplit) {
    case 'full_body':
      workouts.push(...generateFullBodyWorkouts(config));
      break;
    case 'upper_lower':
      workouts.push(...generateUpperLowerWorkouts(config));
      break;
    case 'push_pull_legs':
      workouts.push(...generatePushPullLegsWorkouts(config));
      break;
    case 'body_part':
      workouts.push(...generateBodyPartWorkouts(config));
      break;
    default:
      workouts.push(...generateFullBodyWorkouts(config));
  }

  return {
    name: config.name,
    description: generatePlanDescription(config),
    workouts: workouts.slice(0, config.daysPerWeek),
    schedule: {
      daysPerWeek: config.daysPerWeek,
      sessionMinutes: config.sessionMinutes,
      programWeeks: config.programDuration
    },
    progressionNotes: generateProgressionNotes(config),
    equipmentNeeded: config.equipment
  };
}

// Generate full body workouts
function generateFullBodyWorkouts(config: PlanConfig): Workout[] {
  const workouts: Workout[] = [];
  
  for (let i = 0; i < config.daysPerWeek; i++) {
    const workout: Workout = {
      day: `Day ${i + 1}`,
      name: `Full Body ${String.fromCharCode(65 + i)}`,
      focus: ['Full Body'],
      exercises: [],
      duration: config.sessionMinutes,
      warmup: ['5 min cardio', 'Dynamic stretching'],
      cooldown: ['Static stretching', '5 min walk']
    };

    // Add compound movements first
    if (config.equipment.includes('barbell')) {
      workout.exercises.push({
        name: i % 2 === 0 ? 'Barbell Squat' : 'Romanian Deadlift',
        sets: 4,
        reps: config.primaryGoal === 'strength' ? '4-6' : '8-12',
        rest: config.primaryGoal === 'strength' ? '3min' : '90s',
        notes: 'Focus on form and controlled movement'
      });
    }

    if (config.equipment.includes('dumbbells')) {
      workout.exercises.push({
        name: i % 2 === 0 ? 'Dumbbell Chest Press' : 'Dumbbell Row',
        sets: 3,
        reps: '10-12',
        rest: '60s'
      });
    }

    // Add accessory work
    if (config.targetMuscles.includes('shoulders')) {
      workout.exercises.push({
        name: 'Shoulder Press',
        sets: 3,
        reps: '10-12',
        rest: '60s'
      });
    }

    if (config.targetMuscles.includes('core')) {
      workout.exercises.push({
        name: 'Plank',
        sets: 3,
        reps: '30-60s',
        rest: '30s'
      });
    }

    // Add cardio if requested
    if (config.cardioPreference && config.cardioPreference !== 'minimal') {
      if (config.cardioPreference === 'hiit') {
        workout.exercises.push({
          name: 'HIIT Intervals',
          sets: 5,
          reps: '30s work / 30s rest',
          rest: 'As prescribed'
        });
      } else {
        workout.exercises.push({
          name: 'Steady State Cardio',
          sets: 1,
          reps: '15-20 min',
          rest: 'N/A'
        });
      }
    }

    workouts.push(workout);
  }

  return workouts;
}

// Generate upper/lower workouts
function generateUpperLowerWorkouts(config: PlanConfig): Workout[] {
  const workouts: Workout[] = [];
  const upperDays = Math.ceil(config.daysPerWeek / 2);
  const lowerDays = config.daysPerWeek - upperDays;

  // Generate upper body days
  for (let i = 0; i < upperDays; i++) {
    workouts.push({
      day: `Day ${workouts.length + 1}`,
      name: `Upper Body ${i + 1}`,
      focus: ['Chest', 'Back', 'Shoulders', 'Arms'],
      exercises: generateUpperBodyExercises(config, i === 0),
      duration: config.sessionMinutes,
      warmup: ['Arm circles', 'Band pull-aparts'],
      cooldown: ['Upper body stretches']
    });
  }

  // Generate lower body days
  for (let i = 0; i < lowerDays; i++) {
    workouts.push({
      day: `Day ${workouts.length + 1}`,
      name: `Lower Body ${i + 1}`,
      focus: ['Quads', 'Hamstrings', 'Glutes', 'Calves'],
      exercises: generateLowerBodyExercises(config, i === 0),
      duration: config.sessionMinutes,
      warmup: ['Leg swings', 'Hip circles'],
      cooldown: ['Lower body stretches']
    });
  }

  return workouts;
}

// Generate push/pull/legs workouts
function generatePushPullLegsWorkouts(config: PlanConfig): Workout[] {
  const workouts: Workout[] = [];
  const cycleCount = Math.ceil(config.daysPerWeek / 3);

  for (let cycle = 0; cycle < cycleCount; cycle++) {
    // Push day
    if (workouts.length < config.daysPerWeek) {
      workouts.push({
        day: `Day ${workouts.length + 1}`,
        name: `Push ${cycle + 1}`,
        focus: ['Chest', 'Shoulders', 'Triceps'],
        exercises: generatePushExercises(config),
        duration: config.sessionMinutes,
        warmup: ['Shoulder rotations', 'Light pushups'],
        cooldown: ['Chest and shoulder stretches']
      });
    }

    // Pull day
    if (workouts.length < config.daysPerWeek) {
      workouts.push({
        day: `Day ${workouts.length + 1}`,
        name: `Pull ${cycle + 1}`,
        focus: ['Back', 'Biceps'],
        exercises: generatePullExercises(config),
        duration: config.sessionMinutes,
        warmup: ['Band pull-aparts', 'Arm circles'],
        cooldown: ['Back and arm stretches']
      });
    }

    // Legs day
    if (workouts.length < config.daysPerWeek) {
      workouts.push({
        day: `Day ${workouts.length + 1}`,
        name: `Legs ${cycle + 1}`,
        focus: ['Quads', 'Hamstrings', 'Glutes', 'Calves'],
        exercises: generateLowerBodyExercises(config, cycle === 0),
        duration: config.sessionMinutes,
        warmup: ['Leg swings', 'Bodyweight squats'],
        cooldown: ['Leg stretches']
      });
    }
  }

  return workouts;
}

// Generate body part split workouts
function generateBodyPartWorkouts(config: PlanConfig): Workout[] {
  const workouts: Workout[] = [];
  const bodyParts = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs'];
  
  for (let i = 0; i < config.daysPerWeek && i < bodyParts.length; i++) {
    const bodyPart = bodyParts[i];
    workouts.push({
      day: `Day ${i + 1}`,
      name: `${bodyPart} Day`,
      focus: [bodyPart],
      exercises: generateBodyPartExercises(config, bodyPart),
      duration: config.sessionMinutes,
      warmup: ['5 min cardio', `${bodyPart} specific warmup`],
      cooldown: [`${bodyPart} stretches`]
    });
  }

  return workouts;
}

// Helper functions to generate specific exercises
function generateUpperBodyExercises(config: PlanConfig, isPrimary: boolean): Exercise[] {
  const exercises: Exercise[] = [];
  
  // Chest
  if (config.equipment.includes('barbell')) {
    exercises.push({
      name: isPrimary ? 'Barbell Bench Press' : 'Incline Barbell Press',
      sets: 4,
      reps: config.primaryGoal === 'strength' ? '5-6' : '8-10',
      rest: '2min'
    });
  }

  // Back
  if (config.equipment.includes('pullup_bar')) {
    exercises.push({
      name: 'Pull-ups',
      sets: 3,
      reps: '6-10',
      rest: '90s',
      notes: 'Use assistance if needed'
    });
  }

  // Shoulders
  exercises.push({
    name: 'Overhead Press',
    sets: 3,
    reps: '8-12',
    rest: '90s'
  });

  // Arms
  if (config.includeSupersets) {
    exercises.push({
      name: 'Bicep Curls + Tricep Extensions',
      sets: 3,
      reps: '12-15',
      rest: '60s',
      notes: 'Superset'
    });
  }

  return exercises;
}

function generateLowerBodyExercises(config: PlanConfig, isPrimary: boolean): Exercise[] {
  const exercises: Exercise[] = [];
  
  // Quads dominant
  if (config.equipment.includes('barbell')) {
    exercises.push({
      name: isPrimary ? 'Back Squat' : 'Front Squat',
      sets: 4,
      reps: config.primaryGoal === 'strength' ? '4-6' : '8-12',
      rest: '2-3min'
    });
  }

  // Hip dominant
  exercises.push({
    name: 'Romanian Deadlift',
    sets: 3,
    reps: '8-12',
    rest: '90s'
  });

  // Unilateral
  exercises.push({
    name: 'Walking Lunges',
    sets: 3,
    reps: '10-12 per leg',
    rest: '60s'
  });

  // Calves
  if (config.targetMuscles.includes('calves')) {
    exercises.push({
      name: 'Calf Raises',
      sets: 3,
      reps: '15-20',
      rest: '45s'
    });
  }

  return exercises;
}

function generatePushExercises(config: PlanConfig): Exercise[] {
  const exercises: Exercise[] = [];
  
  exercises.push(
    {
      name: 'Bench Press',
      sets: 4,
      reps: '6-8',
      rest: '2min'
    },
    {
      name: 'Overhead Press',
      sets: 3,
      reps: '8-10',
      rest: '90s'
    },
    {
      name: 'Dips',
      sets: 3,
      reps: '8-12',
      rest: '90s'
    },
    {
      name: 'Lateral Raises',
      sets: 3,
      reps: '12-15',
      rest: '60s'
    }
  );

  return exercises;
}

function generatePullExercises(config: PlanConfig): Exercise[] {
  const exercises: Exercise[] = [];
  
  exercises.push(
    {
      name: 'Deadlift',
      sets: 4,
      reps: '5-6',
      rest: '3min'
    },
    {
      name: 'Pull-ups',
      sets: 3,
      reps: '6-10',
      rest: '90s'
    },
    {
      name: 'Barbell Rows',
      sets: 3,
      reps: '8-10',
      rest: '90s'
    },
    {
      name: 'Face Pulls',
      sets: 3,
      reps: '15-20',
      rest: '60s'
    }
  );

  return exercises;
}

function generateBodyPartExercises(config: PlanConfig, bodyPart: string): Exercise[] {
  switch (bodyPart) {
    case 'Chest':
      return generatePushExercises(config).filter(e => 
        e.name.toLowerCase().includes('press') || 
        e.name.toLowerCase().includes('fly')
      );
    case 'Back':
      return generatePullExercises(config).filter(e => 
        e.name.toLowerCase().includes('row') || 
        e.name.toLowerCase().includes('pull')
      );
    case 'Shoulders':
      return generatePushExercises(config).filter(e => 
        e.name.toLowerCase().includes('press') || 
        e.name.toLowerCase().includes('raise')
      );
    case 'Arms':
      return [
        { name: 'Barbell Curls', sets: 4, reps: '8-10', rest: '60s' },
        { name: 'Hammer Curls', sets: 3, reps: '10-12', rest: '45s' },
        { name: 'Tricep Pushdowns', sets: 4, reps: '10-12', rest: '60s' },
        { name: 'Overhead Tricep Extension', sets: 3, reps: '10-12', rest: '45s' }
      ];
    case 'Legs':
      return generateLowerBodyExercises(config, true);
    default:
      return [];
  }
}

// Generate plan description
function generatePlanDescription(config: PlanConfig): string {
  return `A ${config.programDuration}-week ${config.primaryGoal} program designed for ${config.experience} level trainees. ` +
         `This plan follows a ${config.workoutSplit.replace('_', ' ')} split with ${config.daysPerWeek} training days per week. ` +
         `Each session is designed to last approximately ${config.sessionMinutes} minutes.`;
}

// Generate progression notes
function generateProgressionNotes(config: PlanConfig): string {
  const notes: string[] = [];
  
  if (config.experience === 'beginner') {
    notes.push('Focus on mastering form before increasing weight.');
    notes.push('Increase weight by 2.5-5 lbs when you can complete all sets with good form.');
  } else if (config.experience === 'intermediate') {
    notes.push('Apply progressive overload by increasing weight, reps, or sets weekly.');
    notes.push('Consider deload weeks every 4-6 weeks.');
  } else {
    notes.push('Use advanced techniques like drop sets, rest-pause, or cluster sets.');
    notes.push('Implement periodization with intensity and volume cycles.');
  }

  if (config.primaryGoal === 'strength') {
    notes.push('Prioritize adding weight to the bar on compound movements.');
    notes.push('Rest fully between heavy sets (3-5 minutes).');
  } else if (config.primaryGoal === 'muscle_gain') {
    notes.push('Focus on time under tension and mind-muscle connection.');
    notes.push('Aim for 40-70 reps per muscle group per session.');
  } else if (config.primaryGoal === 'fat_loss') {
    notes.push('Keep rest periods shorter (30-60s) to maintain elevated heart rate.');
    notes.push('Combine with proper nutrition for optimal results.');
  }

  return notes.join(' ');
}


