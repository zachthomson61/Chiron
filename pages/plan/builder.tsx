import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/router';
import { useUser } from '@clerk/nextjs';
import { usePlanFlow } from '@/hooks/usePlanFlow';
import { OneQuestionShell } from '@/components/OneQuestionShell';
import { PlanResultView } from '@/components/PlanResultView';
import { useFeatureFlag } from '@/hooks/useFeatureFlag';
import { trackFlowStart } from '@/lib/telemetry/planBuilder';
import LegacyPlanBuilder from '@/components/LegacyPlanBuilder';

// Loading component
function LoadingScreen() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      <div className="text-center">
        <div className="w-16 h-16 border-4 border-blue-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
        <p className="text-gray-600 dark:text-gray-400">Loading your plan builder...</p>
      </div>
    </div>
  );
}

// Exit confirmation modal
function ExitConfirmation({ 
  isOpen, 
  onConfirm, 
  onCancel 
}: { 
  isOpen: boolean; 
  onConfirm: () => void; 
  onCancel: () => void;
}) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-white dark:bg-gray-900 rounded-2xl p-6 max-w-sm mx-4 shadow-xl">
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mb-2">
          Leave Plan Builder?
        </h3>
        <p className="text-gray-600 dark:text-gray-400 mb-6">
          Your progress has been saved. You can continue where you left off anytime.
        </p>
        <div className="flex gap-3">
          <button
            onClick={onCancel}
            className="flex-1 px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
          >
            Stay
          </button>
          <button
            onClick={onConfirm}
            className="flex-1 px-4 py-2 rounded-lg bg-red-500 text-white hover:bg-red-600 transition-colors"
          >
            Leave
          </button>
        </div>
      </div>
    </div>
  );
}

// Start screen for new users
function StartScreen({ onStart }: { onStart: () => void }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      <div className="max-w-2xl mx-auto px-4 text-center">
        <h1 className="text-4xl md:text-5xl font-bold text-gray-900 dark:text-white mb-4">
          Build Your Perfect Training Plan
        </h1>
        <p className="text-xl text-gray-600 dark:text-gray-400 mb-8">
          Answer a few quick questions and we'll create a personalized workout program just for you.
        </p>
        
        <div className="bg-white dark:bg-gray-900 rounded-2xl p-8 shadow-xl mb-8">
          <div className="grid grid-cols-3 gap-4 mb-8">
            <div className="text-center">
              <div className="text-3xl mb-2">⏱️</div>
              <div className="font-medium text-gray-900 dark:text-white">5 minutes</div>
              <div className="text-sm text-gray-500 dark:text-gray-400">Average time</div>
            </div>
            <div className="text-center">
              <div className="text-3xl mb-2">📊</div>
              <div className="font-medium text-gray-900 dark:text-white">Personalized</div>
              <div className="text-sm text-gray-500 dark:text-gray-400">To your goals</div>
            </div>
            <div className="text-center">
              <div className="text-3xl mb-2">🎯</div>
              <div className="font-medium text-gray-900 dark:text-white">Science-based</div>
              <div className="text-sm text-gray-500 dark:text-gray-400">Proven methods</div>
            </div>
          </div>
          
          <button
            onClick={onStart}
            className="w-full px-6 py-4 bg-gradient-to-r from-blue-500 to-purple-500 text-white rounded-xl font-medium text-lg hover:shadow-lg transform hover:-translate-y-0.5 transition-all"
          >
            Start Building My Plan
          </button>
        </div>
        
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Your progress is automatically saved • You can return anytime
        </p>
      </div>
    </div>
  );
}

export default function PlanBuilder() {
  const router = useRouter();
  const { user, isLoaded: userLoaded } = useUser();
  const [showExitConfirm, setShowExitConfirm] = useState(false);
  const [hasStarted, setHasStarted] = useState(false);
  
  // Check feature flag
  const isOqfEnabled = useFeatureFlag('plan_builder_oqf');
  const forceVariant = router.query.variant === 'oqf';
  const shouldUseOqf = isOqfEnabled || forceVariant;
  
  // Initialize plan flow
  const {
    state,
    currentStep,
    progress,
    canGoBack,
    isLastStep,
    submit,
    back,
    reset,
    jumpToStep,
    saveState
  } = usePlanFlow({
    userId: user?.id,
    autoSave: true,
    syncToServer: !!user?.id
  });

  // Show legacy builder if feature flag is off
  if (!shouldUseOqf) {
    return <LegacyPlanBuilder />;
  }

  // Check if user has existing progress
  const hasExistingProgress = state.history.length > 0;

  // Handle starting the flow
  const handleStart = () => {
    setHasStarted(true);
    if (!hasExistingProgress) {
      trackFlowStart();
    }
  };

  // Handle exit
  const handleExit = () => {
    setShowExitConfirm(true);
  };

  const confirmExit = async () => {
    await saveState();
    router.push('/dashboard');
  };

  // Handle keyboard navigation
  useEffect(() => {
    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      if (state.history.length > 0) {
        e.preventDefault();
        e.returnValue = 'Your progress will be saved.';
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [state.history]);

  // Show loading while user data loads
  if (!userLoaded) {
    return <LoadingScreen />;
  }

  // Show start screen if not started and no existing progress
  if (!hasStarted && !hasExistingProgress) {
    return <StartScreen onStart={handleStart} />;
  }

  // Show result view if we've reached the end
  if (state.current === 'RESULT') {
    return (
      <PlanResultView
        answers={state.answers}
        onEdit={jumpToStep}
        onStartOver={reset}
        userId={user?.id}
      />
    );
  }

  // Show the current question
  if (!currentStep) {
    return <LoadingScreen />;
  }

  return (
    <>
      <OneQuestionShell
        step={currentStep}
        currentAnswer={state.answers[currentStep.id]}
        progress={progress}
        canGoBack={canGoBack}
        isLastStep={isLastStep}
        onSubmit={submit}
        onBack={back}
        onExit={handleExit}
      />
      
      <ExitConfirmation
        isOpen={showExitConfirm}
        onConfirm={confirmExit}
        onCancel={() => setShowExitConfirm(false)}
      />
    </>
  );
}







