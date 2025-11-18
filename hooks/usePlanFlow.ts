import { useCallback, useMemo, useState, useEffect } from 'react';
import { flow, calculatePathLength, type FlowState, type Answer, type StepId } from '@/flow/config';
import { trackEvent } from '@/lib/telemetry/planBuilder';

const STORAGE_VERSION = 'v2';
const STORAGE_KEY_PREFIX = 'planBuilder';

export interface UsePlanFlowOptions {
  userId?: string;
  autoSave?: boolean;
  syncToServer?: boolean;
}

export interface UsePlanFlowReturn {
  state: FlowState;
  currentStep: typeof flow.steps[keyof typeof flow.steps] | null;
  progress: number;
  canGoBack: boolean;
  canContinue: boolean;
  isLastStep: boolean;
  submit: (answer: Answer) => Promise<{ ok: boolean; error?: string }>;
  back: () => void;
  reset: () => void;
  jumpToStep: (stepId: StepId) => void;
  saveState: () => Promise<void>;
}

// Create initial state
function createInitialState(): FlowState {
  return {
    current: flow.start,
    answers: {},
    history: [],
    startedAt: Date.now(),
    lastUpdatedAt: Date.now()
  };
}

// Load state from localStorage
function loadStateFromStorage(userId?: string): FlowState | null {
  const key = `${STORAGE_KEY_PREFIX}:${STORAGE_VERSION}:${userId ?? 'anon'}`;
  try {
    const stored = localStorage.getItem(key);
    if (!stored) return null;
    
    const parsed = JSON.parse(stored);
    // Validate the loaded state has required fields
    if (!parsed.current || !parsed.answers || !parsed.history) {
      return null;
    }
    return parsed as FlowState;
  } catch (error) {
    console.error('Failed to load state from storage:', error);
    return null;
  }
}

// Save state to localStorage
function saveStateToStorage(state: FlowState, userId?: string): void {
  const key = `${STORAGE_KEY_PREFIX}:${STORAGE_VERSION}:${userId ?? 'anon'}`;
  try {
    localStorage.setItem(key, JSON.stringify(state));
  } catch (error) {
    console.error('Failed to save state to storage:', error);
  }
}

// Save state to server
async function saveStateToServer(
  state: FlowState, 
  userId?: string,
  isComplete = false
): Promise<void> {
  if (!userId) return;
  
  try {
    const endpoint = isComplete ? '/api/plan/complete' : '/api/plan/answers';
    await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userId,
        state,
        timestamp: Date.now(),
        isComplete
      })
    });
  } catch (error) {
    console.error('Failed to save state to server:', error);
  }
}

export function usePlanFlow({
  userId,
  autoSave = true,
  syncToServer = true
}: UsePlanFlowOptions = {}): UsePlanFlowReturn {
  // Initialize state with localStorage data if available
  const [state, setState] = useState<FlowState>(() => {
    const stored = loadStateFromStorage(userId);
    if (stored) {
      trackEvent('oqf_resume', { 
        stepId: stored.current,
        answersCount: Object.keys(stored.answers).length
      });
      return stored;
    }
    
    const initial = createInitialState();
    trackEvent('oqf_start', {});
    return initial;
  });

  // Get current step
  const currentStep = useMemo(() => {
    if (state.current === 'RESULT') return null;
    return flow.steps[state.current] || null;
  }, [state.current]);

  // Calculate progress
  const progress = useMemo(() => {
    const totalSteps = calculatePathLength(state.answers);
    const completedSteps = state.history.length;
    
    if (totalSteps === 0) return 0;
    
    // If we're at RESULT, we're 100% complete
    if (state.current === 'RESULT') return 1;
    
    // Otherwise calculate based on completed vs estimated total
    return Math.min(completedSteps / totalSteps, 0.95);
  }, [state.answers, state.history, state.current]);

  // Check if we can go back
  const canGoBack = state.history.length > 0;

  // Check if we're at the last step
  const isLastStep = useMemo(() => {
    if (!currentStep) return false;
    // Try to predict if the next step would be RESULT
    const mockAnswer = currentStep.type === 'yesno' ? false : 
                      currentStep.options?.[0]?.value || '';
    return currentStep.next(mockAnswer, state.answers) === 'RESULT';
  }, [currentStep, state.answers]);

  // Check if we can continue (used for UI state)
  const canContinue = currentStep?.required === false || false;

  // Auto-save to localStorage
  useEffect(() => {
    if (!autoSave) return;
    saveStateToStorage(state, userId);
  }, [state, userId, autoSave]);

  // Submit an answer
  const submit = useCallback(async (answer: Answer): Promise<{ ok: boolean; error?: string }> => {
    if (!currentStep) {
      return { ok: false, error: 'No current step' };
    }

    const startTime = Date.now();

    // Validate the answer
    if (currentStep.validate) {
      const error = currentStep.validate(answer);
      if (error) {
        trackEvent('oqf_validation_error', {
          stepId: state.current,
          error
        });
        return { ok: false, error };
      }
    }

    // Determine next step
    const nextId = currentStep.next(answer, state.answers);

    // Update state
    const newState: FlowState = {
      current: nextId,
      answers: { ...state.answers, [state.current]: answer },
      history: [...state.history, state.current],
      startedAt: state.startedAt,
      lastUpdatedAt: Date.now()
    };

    setState(newState);

    // Track analytics
    trackEvent('oqf_answer_submit', {
      stepId: state.current,
      timeOnStep: startTime - state.lastUpdatedAt,
      answersCount: Object.keys(newState.answers).length,
      isLastStep: nextId === 'RESULT'
    });

    // Track step view for the next step
    if (nextId !== 'RESULT') {
      trackEvent('oqf_step_view', {
        stepId: nextId,
        from: state.current
      });
    }

    // Save to server if enabled
    if (syncToServer) {
      await saveStateToServer(newState, userId, nextId === 'RESULT');
    }

    // If we reached the result, trigger completion
    if (nextId === 'RESULT') {
      trackEvent('oqf_complete', {
        totalSteps: newState.history.length,
        duration: Date.now() - newState.startedAt
      });
    }

    return { ok: true };
  }, [state, currentStep, userId, syncToServer]);

  // Go back to previous step
  const back = useCallback(() => {
    if (state.history.length === 0) return;

    const previousStep = state.history[state.history.length - 1];
    const newHistory = state.history.slice(0, -1);

    const newState: FlowState = {
      ...state,
      current: previousStep,
      history: newHistory,
      lastUpdatedAt: Date.now()
    };

    setState(newState);

    trackEvent('oqf_back_click', {
      from: state.current,
      to: previousStep
    });

    // Save to server if enabled
    if (syncToServer) {
      saveStateToServer(newState, userId).catch(console.error);
    }
  }, [state, userId, syncToServer]);

  // Reset the entire flow
  const reset = useCallback(() => {
    const newState = createInitialState();
    setState(newState);
    
    // Clear localStorage
    const key = `${STORAGE_KEY_PREFIX}:${STORAGE_VERSION}:${userId ?? 'anon'}`;
    localStorage.removeItem(key);

    trackEvent('oqf_reset', {
      fromStep: state.current,
      answersCount: Object.keys(state.answers).length
    });

    // Clear server state if enabled
    if (syncToServer && userId) {
      fetch('/api/plan/clear', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId })
      }).catch(console.error);
    }
  }, [state, userId, syncToServer]);

  // Jump to a specific step (for edit functionality)
  const jumpToStep = useCallback((stepId: StepId) => {
    // Find the index of this step in history
    const stepIndex = state.history.indexOf(stepId);
    
    if (stepIndex === -1) {
      console.error(`Cannot jump to step ${stepId}: not in history`);
      return;
    }

    // Create new state with truncated history
    const newHistory = state.history.slice(0, stepIndex);
    const newState: FlowState = {
      ...state,
      current: stepId,
      history: newHistory,
      lastUpdatedAt: Date.now()
    };

    setState(newState);

    trackEvent('oqf_jump', {
      from: state.current,
      to: stepId
    });
  }, [state]);

  // Manual save function
  const saveState = useCallback(async () => {
    saveStateToStorage(state, userId);
    if (syncToServer) {
      await saveStateToServer(state, userId);
    }
  }, [state, userId, syncToServer]);

  return {
    state,
    currentStep,
    progress,
    canGoBack,
    canContinue,
    isLastStep,
    submit,
    back,
    reset,
    jumpToStep,
    saveState
  };
}







