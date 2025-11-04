import React, { useCallback, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronLeft, ArrowRight, X } from 'lucide-react';
import type { Step, Answer } from '@/flow/config';
import { 
  SingleChoice, 
  MultiChoice, 
  NumberInput, 
  RangeSlider, 
  ChipSelect, 
  YesNoToggle, 
  TimeInput,
  TextInput 
} from './InputControls';

interface OneQuestionShellProps {
  step: Step;
  currentAnswer?: Answer;
  progress: number;
  canGoBack: boolean;
  isLastStep: boolean;
  onSubmit: (answer: Answer) => Promise<{ ok: boolean; error?: string }>;
  onBack: () => void;
  onExit: () => void;
}

export function OneQuestionShell({
  step,
  currentAnswer,
  progress,
  canGoBack,
  isLastStep,
  onSubmit,
  onBack,
  onExit
}: OneQuestionShellProps) {
  const [answer, setAnswer] = React.useState<Answer | undefined>(currentAnswer);
  const [error, setError] = React.useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = React.useState(false);
  const submitButtonRef = useRef<HTMLButtonElement>(null);

  // Reset answer when step changes
  useEffect(() => {
    setAnswer(currentAnswer);
    setError(null);
  }, [step.id, currentAnswer]);

  // Handle form submission
  const handleSubmit = useCallback(async () => {
    if (answer === undefined && step.required) {
      setError('This field is required');
      return;
    }

    // Validate locally first
    if (step.validate && answer !== undefined) {
      const validationError = step.validate(answer);
      if (validationError) {
        setError(validationError);
        return;
      }
    }

    setIsSubmitting(true);
    setError(null);

    try {
      const result = await onSubmit(answer!);
      if (!result.ok) {
        setError(result.error || 'Something went wrong');
      }
    } finally {
      setIsSubmitting(false);
    }
  }, [answer, step, onSubmit]);

  // Handle keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Enter to submit
      if (e.key === 'Enter' && !e.shiftKey) {
        // Don't submit if we're in a textarea
        if ((e.target as HTMLElement).tagName === 'TEXTAREA') return;
        
        e.preventDefault();
        submitButtonRef.current?.click();
      }
      
      // Escape to exit
      if (e.key === 'Escape') {
        onExit();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onExit]);

  // Check if we can submit
  const canSubmit = answer !== undefined || !step.required;

  // Render the appropriate input control
  const renderControl = () => {
    const commonProps = {
      value: answer,
      onChange: (newValue: Answer) => {
        setAnswer(newValue);
        setError(null);
      },
      error: error || undefined
    };

    switch (step.type) {
      case 'single':
        return <SingleChoice {...commonProps} options={step.options || []} />;
      
      case 'multi':
        return <MultiChoice {...commonProps} options={step.options || []} />;
      
      case 'number':
        return (
          <NumberInput 
            {...commonProps} 
            min={step.min}
            max={step.max}
            placeholder={step.placeholder}
          />
        );
      
      case 'range':
        return (
          <RangeSlider 
            {...commonProps}
            min={step.min || 0}
            max={step.max || 100}
            step={step.step || 1}
            unit={step.unit}
          />
        );
      
      case 'chips':
        return <ChipSelect {...commonProps} options={step.options || []} />;
      
      case 'yesno':
        return <YesNoToggle {...commonProps} />;
      
      case 'time':
        return <TimeInput {...commonProps} />;
      
      case 'text':
        return (
          <TextInput 
            {...commonProps}
            placeholder={step.placeholder}
            multiline={false}
          />
        );
      
      default:
        return null;
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      {/* Progress Bar */}
      <div className="fixed top-0 left-0 right-0 h-1 bg-gray-200 dark:bg-gray-700 z-50">
        <motion.div
          className="h-full bg-gradient-to-r from-blue-500 to-purple-500"
          initial={{ width: 0 }}
          animate={{ width: `${progress * 100}%` }}
          transition={{ duration: 0.3, ease: 'easeOut' }}
        />
      </div>

      {/* Header */}
      <header className="fixed top-0 left-0 right-0 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-700 z-40">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <button
            onClick={onBack}
            disabled={!canGoBack}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            aria-label="Go back"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>

          <span className="text-sm font-medium text-gray-500 dark:text-gray-400">
            {Math.round(progress * 100)}% Complete
          </span>

          <button
            onClick={onExit}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
            aria-label="Exit"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
      </header>

      {/* Main Content */}
      <main className="pt-20 pb-32 px-4">
        <div className="max-w-2xl mx-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={step.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.3 }}
              className="bg-white dark:bg-gray-900 rounded-2xl shadow-xl p-8 md:p-12"
            >
              {/* Question */}
              <h1 className="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white mb-2">
                {step.prompt}
              </h1>

              {/* Helper text */}
              {step.helper && (
                <p className="text-gray-600 dark:text-gray-400 mb-8">
                  {step.helper}
                </p>
              )}

              {/* Input Control */}
              <div className="mb-8">
                {renderControl()}
              </div>

              {/* Error Message */}
              {error && (
                <motion.div
                  initial={{ opacity: 0, y: -10 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="mb-6 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg"
                  role="alert"
                >
                  <p className="text-red-600 dark:text-red-400 text-sm">{error}</p>
                </motion.div>
              )}

              {/* Action Buttons */}
              <div className="flex items-center justify-between gap-4">
                {/* Skip button (if optional) */}
                {!step.required && (
                  <button
                    onClick={() => handleSubmit()}
                    disabled={isSubmitting}
                    className="text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors text-sm"
                  >
                    Skip this question
                  </button>
                )}

                <div className="flex-1" />

                {/* Continue button */}
                <button
                  ref={submitButtonRef}
                  onClick={handleSubmit}
                  disabled={!canSubmit || isSubmitting}
                  className={`
                    px-6 py-3 rounded-lg font-medium transition-all
                    flex items-center gap-2 min-w-[120px] justify-center
                    ${canSubmit
                      ? 'bg-gradient-to-r from-blue-500 to-purple-500 text-white hover:shadow-lg transform hover:-translate-y-0.5'
                      : 'bg-gray-200 dark:bg-gray-700 text-gray-400 dark:text-gray-500 cursor-not-allowed'
                    }
                  `}
                >
                  {isSubmitting ? (
                    <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  ) : (
                    <>
                      {isLastStep ? 'Finish' : 'Continue'}
                      <ArrowRight className="w-4 h-4" />
                    </>
                  )}
                </button>
              </div>
            </motion.div>
          </AnimatePresence>
        </div>
      </main>

      {/* Keyboard hints */}
      <div className="fixed bottom-4 left-4 right-4 max-w-2xl mx-auto">
        <div className="flex items-center justify-center gap-6 text-xs text-gray-500 dark:text-gray-400">
          <span className="flex items-center gap-1">
            <kbd className="px-2 py-1 bg-gray-100 dark:bg-gray-800 rounded">Enter</kbd>
            to continue
          </span>
          <span className="flex items-center gap-1">
            <kbd className="px-2 py-1 bg-gray-100 dark:bg-gray-800 rounded">Esc</kbd>
            to exit
          </span>
        </div>
      </div>
    </div>
  );
}

