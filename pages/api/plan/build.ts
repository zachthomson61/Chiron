import type { NextApiRequest, NextApiResponse } from 'next';
import { getAuth } from '@clerk/nextjs/server';
import { prisma } from '@/lib/prisma';
import { generatePlanFromAnswers } from '@/lib/planGenerator';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Get user from Clerk
    const { userId } = getAuth(req);
    
    const { answers } = req.body;

    // Validate required fields
    if (!answers || Object.keys(answers).length === 0) {
      return res.status(400).json({ 
        error: 'No answers provided' 
      });
    }

    // Extract key answers for plan generation
    const planConfig = {
      name: answers.plan_name || 'My Training Plan',
      primaryGoal: answers.primary_goal,
      experience: answers.experience_level,
      daysPerWeek: Number(answers.days_per_week) || 3,
      sessionMinutes: Number(answers.session_duration || answers.session_duration_short) || 45,
      targetMuscles: answers.target_muscles || [],
      workoutSplit: answers.workout_split,
      customSplit: answers.custom_split_design,
      equipment: answers.equipment_available || [],
      injuries: answers.injury_details,
      exerciseVariety: answers.exercise_variety || 'balanced',
      includeSupersets: answers.supersets === true,
      programDuration: Number(answers.program_duration) || 8,
      startDate: answers.start_date === 'today' ? new Date() :
                 answers.start_date === 'tomorrow' ? new Date(Date.now() + 86400000) :
                 answers.start_date === 'next_monday' ? getNextMonday() :
                 answers.custom_start_date ? new Date(answers.custom_start_date) :
                 new Date(),
      cardioPreference: answers.cardio_preference,
      sport: answers.sport_type,
      includeTutorials: false, // Tutorial question removed from flow
      // New personalization fields
      currentActivityLevel: answers.current_activity_level,
      caloricTracking: answers.caloric_tracking,
      dietPhase: answers.diet_phase,
      specificWeaknesses: answers.specific_weaknesses || [],
      trainingPreferencesLifting: answers.training_preferences_lifting || [],
      trainingPreferencesCardio: answers.training_preferences_cardio,
      cardioTypePreference: answers.cardio_type_preference || [],
      trainingIntensity: answers.training_intensity
    };

    // Generate the plan using AI or algorithmic approach
    const generatedPlan = await generatePlanFromAnswers(planConfig);

    // Save to database if user is authenticated
    let savedPlan = null;
    if (userId) {
      savedPlan = await prisma.plan.create({
        data: {
          userId,
          name: generatedPlan.name,
          description: generatedPlan.description,
          config: planConfig,
          workouts: generatedPlan.workouts,
          schedule: generatedPlan.schedule,
          metadata: {
            generatedFrom: 'oqf',
            answers,
            generatedAt: new Date()
          },
          isActive: true
        }
      });

      // Mark any draft as completed
      await prisma.planDraft.updateMany({
        where: {
          userId,
          status: 'in_progress'
        },
        data: {
          status: 'completed',
          completedPlanId: savedPlan.id,
          completedAt: new Date()
        }
      });

      // Log analytics event
      await prisma.analyticsEvent.create({
        data: {
          userId,
          event: 'plan_generated',
          properties: {
            planId: savedPlan.id,
            method: 'oqf',
            daysPerWeek: planConfig.daysPerWeek,
            primaryGoal: planConfig.primaryGoal,
            duration: planConfig.programDuration
          }
        }
      });
    }

    // Return the generated plan
    res.status(200).json({
      id: savedPlan?.id || `temp_${Date.now()}`,
      name: generatedPlan.name,
      description: generatedPlan.description,
      workouts: generatedPlan.workouts,
      schedule: {
        daysPerWeek: planConfig.daysPerWeek,
        sessionMinutes: planConfig.sessionMinutes,
        programWeeks: planConfig.programDuration
      },
      createdAt: new Date()
    });
  } catch (error) {
    console.error('Error generating plan:', error);
    res.status(500).json({ 
      error: 'Failed to generate plan',
      details: process.env.NODE_ENV === 'development' ? error : undefined
    });
  }
}

// Helper function to get next Monday
function getNextMonday(): Date {
  const date = new Date();
  const day = date.getDay();
  const diff = day === 0 ? 1 : 8 - day; // If Sunday, next day. Otherwise, days until next Monday
  date.setDate(date.getDate() + diff);
  date.setHours(0, 0, 0, 0);
  return date;
}


