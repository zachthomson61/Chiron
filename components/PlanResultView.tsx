import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Edit2, Check, Loader2, Download, Share2, Calendar, ChevronRight, RefreshCw } from 'lucide-react';
import { flow, type Answer, type StepId } from '@/flow/config';
import { trackResultSuccess, trackResultError } from '@/lib/telemetry/planBuilder';
import { useRouter } from 'next/router';

interface PlanResultViewProps {
  answers: Record<StepId, Answer>;
  onEdit: (stepId: StepId) => void;
  onStartOver: () => void;
  userId?: string;
}

interface GeneratedPlan {
  id: string;
  name: string;
  workouts: Array<{
    day: string;
    name: string;
    exercises: Array<{
      name: string;
      sets: number;
      reps: string;
      rest: string;
    }>;
  }>;
  schedule: {
    daysPerWeek: number;
    sessionMinutes: number;
    programWeeks: number;
  };
  createdAt: Date;
}

// Format answer for display
function formatAnswer(stepId: StepId, answer: Answer): string {
  const step = flow.steps[stepId];
  if (!step) return String(answer);

  switch (step.type) {
    case 'single':
    case 'chips':
      const option = step.options?.find(o => o.value === answer);
      return option?.label || String(answer);
    
    case 'multi':
      if (Array.isArray(answer)) {
        return answer
          .map(v => step.options?.find(o => o.value === v)?.label || v)
          .join(', ');
      }
      return String(answer);
    
    case 'yesno':
      return answer ? 'Yes' : 'No';
    
    case 'range':
    case 'number':
      return `${answer}${step.unit ? ` ${step.unit}` : ''}`;
    
    case 'time':
      return String(answer);
    
    default:
      return String(answer);
  }
}

// Answer summary card
function AnswerCard({ 
  stepId, 
  answer, 
  onEdit 
}: { 
  stepId: StepId; 
  answer: Answer; 
  onEdit: () => void;
}) {
  const step = flow.steps[stepId];
  if (!step) return null;

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-gray-50 dark:bg-gray-800 rounded-xl p-4"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1">
          <p className="text-sm text-gray-500 dark:text-gray-400 mb-1">
            {step.prompt}
          </p>
          <p className="font-medium text-gray-900 dark:text-white">
            {formatAnswer(stepId, answer)}
          </p>
        </div>
        <button
          onClick={onEdit}
          className="p-2 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
          aria-label={`Edit ${step.prompt}`}
        >
          <Edit2 className="w-4 h-4 text-gray-500" />
        </button>
      </div>
    </motion.div>
  );
}

export function PlanResultView({ answers, onEdit, onStartOver, userId }: PlanResultViewProps) {
  const router = useRouter();
  const [isGenerating, setIsGenerating] = useState(false);
  const [generatedPlan, setGeneratedPlan] = useState<GeneratedPlan | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showAllAnswers, setShowAllAnswers] = useState(false);

  // Auto-generate plan on mount
  useEffect(() => {
    generatePlan();
  }, []);

  // Generate the plan
  const generatePlan = async () => {
    setIsGenerating(true);
    setError(null);

    try {
      const response = await fetch('/api/plan/build', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          answers,
          userId 
        })
      });

      if (!response.ok) {
        throw new Error('Failed to generate plan');
      }

      const plan = await response.json();
      setGeneratedPlan(plan);
      trackResultSuccess(plan.id);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'An error occurred';
      setError(errorMessage);
      trackResultError(errorMessage);
    } finally {
      setIsGenerating(false);
    }
  };

  // Get important answer summaries
  const getSummaryAnswers = () => {
    const summaryKeys: StepId[] = [
      'plan_name',
      'primary_goal',
      'days_per_week',
      'session_duration',
      'workout_split',
      'program_duration'
    ];

    return Object.entries(answers)
      .filter(([key]) => summaryKeys.includes(key))
      .slice(0, 6);
  };

  const summaryAnswers = getSummaryAnswers();
  const allAnswerEntries = Object.entries(answers);

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      {/* Header */}
      <header className="bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-700">
        <div className="max-w-7xl mx-auto px-4 py-6">
          <div className="flex items-center justify-between">
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
              Your Training Plan
            </h1>
            <button
              onClick={onStartOver}
              className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
              Start Over
            </button>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 py-8">
        <div className="grid lg:grid-cols-3 gap-8">
          {/* Left Column - Plan Summary */}
          <div className="lg:col-span-2 space-y-6">
            {/* Generation Status */}
            {isGenerating && (
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="bg-white dark:bg-gray-900 rounded-2xl shadow-xl p-8 text-center"
              >
                <Loader2 className="w-12 h-12 animate-spin text-blue-500 mx-auto mb-4" />
                <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-2">
                  Creating Your Plan...
                </h2>
                <p className="text-gray-600 dark:text-gray-400">
                  This usually takes 10-15 seconds
                </p>
              </motion.div>
            )}

            {/* Error State */}
            {error && (
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-2xl p-6"
              >
                <h3 className="text-lg font-semibold text-red-800 dark:text-red-200 mb-2">
                  Generation Failed
                </h3>
                <p className="text-red-600 dark:text-red-400 mb-4">{error}</p>
                <button
                  onClick={generatePlan}
                  className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors"
                >
                  Try Again
                </button>
              </motion.div>
            )}

            {/* Generated Plan */}
            {generatedPlan && (
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="bg-white dark:bg-gray-900 rounded-2xl shadow-xl p-8"
              >
                <div className="flex items-start justify-between mb-6">
                  <div>
                    <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                      {generatedPlan.name}
                    </h2>
                    <div className="flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
                      <span>{generatedPlan.schedule.daysPerWeek} days/week</span>
                      <span>•</span>
                      <span>{generatedPlan.schedule.sessionMinutes} min/session</span>
                      <span>•</span>
                      <span>{generatedPlan.schedule.programWeeks} weeks</span>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors">
                      <Download className="w-5 h-5" />
                    </button>
                    <button className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors">
                      <Share2 className="w-5 h-5" />
                    </button>
                  </div>
                </div>

                {/* Workout Preview */}
                <div className="space-y-4">
                  {generatedPlan.workouts.slice(0, 3).map((workout, idx) => (
                    <div key={idx} className="border border-gray-200 dark:border-gray-700 rounded-xl p-4">
                      <h3 className="font-semibold text-gray-900 dark:text-white mb-3">
                        {workout.day}: {workout.name}
                      </h3>
                      <div className="space-y-2">
                        {workout.exercises.map((exercise, exIdx) => (
                          <div key={exIdx} className="flex items-center justify-between text-sm">
                            <span className="text-gray-700 dark:text-gray-300">
                              {exercise.name}
                            </span>
                            <span className="text-gray-500 dark:text-gray-400">
                              {exercise.sets} × {exercise.reps}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>

                {/* View Full Plan Button */}
                <button
                  onClick={() => router.push(`/plan/${generatedPlan.id}`)}
                  className="w-full mt-6 px-6 py-3 bg-gradient-to-r from-blue-500 to-purple-500 text-white rounded-xl font-medium hover:shadow-lg transform hover:-translate-y-0.5 transition-all flex items-center justify-center gap-2"
                >
                  View Full Plan
                  <ChevronRight className="w-5 h-5" />
                </button>
              </motion.div>
            )}
          </div>

          {/* Right Column - Answer Summary */}
          <div className="space-y-6">
            <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-xl p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                  Your Selections
                </h3>
                <button
                  onClick={() => setShowAllAnswers(!showAllAnswers)}
                  className="text-sm text-blue-500 hover:text-blue-600"
                >
                  {showAllAnswers ? 'Show less' : `Show all (${allAnswerEntries.length})`}
                </button>
              </div>

              <div className="space-y-3">
                {(showAllAnswers ? allAnswerEntries : summaryAnswers).map(([stepId, answer]) => (
                  <AnswerCard
                    key={stepId}
                    stepId={stepId}
                    answer={answer}
                    onEdit={() => onEdit(stepId)}
                  />
                ))}
              </div>
            </div>

            {/* Quick Actions */}
            <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-xl p-6">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
                Quick Actions
              </h3>
              <div className="space-y-3">
                <button className="w-full px-4 py-3 bg-gray-100 dark:bg-gray-800 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors flex items-center gap-3">
                  <Calendar className="w-5 h-5" />
                  <span>Add to Calendar</span>
                </button>
                <button className="w-full px-4 py-3 bg-gray-100 dark:bg-gray-800 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors flex items-center gap-3">
                  <Share2 className="w-5 h-5" />
                  <span>Share with Coach</span>
                </button>
                <button className="w-full px-4 py-3 bg-gray-100 dark:bg-gray-800 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors flex items-center gap-3">
                  <Download className="w-5 h-5" />
                  <span>Export PDF</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

