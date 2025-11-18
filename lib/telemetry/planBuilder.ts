// Telemetry event helpers for Plan Builder OQF (One Question Flow)

export type PlanBuilderEvent = 
  | 'oqf_start'
  | 'oqf_resume'
  | 'oqf_view'
  | 'oqf_step_view'
  | 'oqf_answer_submit'
  | 'oqf_validation_error'
  | 'oqf_back_click'
  | 'oqf_jump'
  | 'oqf_abandon'
  | 'oqf_complete'
  | 'oqf_reset'
  | 'oqf_result_success'
  | 'oqf_result_error'
  | 'oqf_edit_answer'
  | 'oqf_save_draft'
  | 'oqf_load_draft';

export interface EventProperties {
  // Common properties
  stepId?: string;
  variant?: string;
  userId?: string;
  sessionId?: string;
  timestamp?: number;
  
  // Flow properties
  from?: string;
  to?: string;
  answersCount?: number;
  pathLength?: number;
  progress?: number;
  
  // Timing properties
  timeOnStep?: number;
  duration?: number;
  
  // Interaction properties
  interactionType?: 'click' | 'keyboard' | 'touch';
  isLastStep?: boolean;
  
  // Error properties
  error?: string;
  errorType?: string;
  
  // Result properties
  planId?: string;
  totalSteps?: number;
  completionRate?: number;
}

// Analytics service interface
interface AnalyticsService {
  track(event: string, properties?: Record<string, any>): void;
  identify(userId: string, traits?: Record<string, any>): void;
  page(name?: string, properties?: Record<string, any>): void;
}

// Mock analytics service for development
class MockAnalytics implements AnalyticsService {
  track(event: string, properties?: Record<string, any>): void {
    if (process.env.NODE_ENV === 'development') {
      console.log('[Analytics]', event, properties);
    }
  }
  
  identify(userId: string, traits?: Record<string, any>): void {
    if (process.env.NODE_ENV === 'development') {
      console.log('[Analytics Identify]', userId, traits);
    }
  }
  
  page(name?: string, properties?: Record<string, any>): void {
    if (process.env.NODE_ENV === 'development') {
      console.log('[Analytics Page]', name, properties);
    }
  }
}

// Get analytics service (could be Segment, Amplitude, Mixpanel, etc.)
function getAnalytics(): AnalyticsService {
  // Check if we have a real analytics service available
  if (typeof window !== 'undefined' && (window as any).analytics) {
    return (window as any).analytics;
  }
  
  // Check for Google Analytics
  if (typeof window !== 'undefined' && (window as any).gtag) {
    return {
      track: (event, properties) => {
        (window as any).gtag('event', event, properties);
      },
      identify: () => {},
      page: () => {}
    };
  }
  
  // Fallback to mock
  return new MockAnalytics();
}

// Session management
let sessionId: string | null = null;
let sessionStartTime: number | null = null;

function getSessionId(): string {
  if (!sessionId) {
    sessionId = `oqf_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    sessionStartTime = Date.now();
  }
  return sessionId;
}

// Main tracking function
export function trackEvent(
  event: PlanBuilderEvent,
  properties: EventProperties = {}
): void {
  const analytics = getAnalytics();
  
  // Add common properties
  const enrichedProperties: EventProperties = {
    ...properties,
    timestamp: Date.now(),
    sessionId: getSessionId(),
    variant: 'oqf', // One Question Flow variant
  };
  
  // Add session duration for completion events
  if (event === 'oqf_complete' || event === 'oqf_abandon') {
    if (sessionStartTime) {
      enrichedProperties.duration = Date.now() - sessionStartTime;
    }
  }
  
  // Track the event
  analytics.track(event, enrichedProperties);
  
  // Send to server for server-side analytics
  if (typeof window !== 'undefined' && window.fetch) {
    sendToServer(event, enrichedProperties).catch(console.error);
  }
}

// Send events to server
async function sendToServer(
  event: PlanBuilderEvent,
  properties: EventProperties
): Promise<void> {
  try {
    await fetch('/api/analytics/track', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ event, properties })
    });
  } catch (error) {
    // Silently fail - don't break the user experience
    if (process.env.NODE_ENV === 'development') {
      console.error('Failed to send analytics to server:', error);
    }
  }
}

// Funnel tracking
export interface FunnelStep {
  stepId: string;
  timestamp: number;
  timeOnStep?: number;
}

class FunnelTracker {
  private steps: FunnelStep[] = [];
  private lastStepTime: number = Date.now();
  
  addStep(stepId: string): void {
    const now = Date.now();
    const timeOnStep = now - this.lastStepTime;
    
    this.steps.push({
      stepId,
      timestamp: now,
      timeOnStep
    });
    
    this.lastStepTime = now;
  }
  
  getSteps(): FunnelStep[] {
    return [...this.steps];
  }
  
  getDropoffRate(): number {
    if (this.steps.length === 0) return 0;
    // Calculate based on expected vs actual steps
    const expectedSteps = 12; // From flow config
    return 1 - (this.steps.length / expectedSteps);
  }
  
  reset(): void {
    this.steps = [];
    this.lastStepTime = Date.now();
  }
}

export const funnelTracker = new FunnelTracker();

// Convenience functions for common events
export function trackFlowStart(): void {
  funnelTracker.reset();
  trackEvent('oqf_start');
}

export function trackStepView(stepId: string, from?: string): void {
  funnelTracker.addStep(stepId);
  trackEvent('oqf_step_view', { stepId, from });
}

export function trackAnswerSubmit(
  stepId: string,
  timeOnStep: number,
  isLastStep: boolean = false
): void {
  trackEvent('oqf_answer_submit', {
    stepId,
    timeOnStep,
    isLastStep,
    answersCount: funnelTracker.getSteps().length
  });
}

export function trackValidationError(stepId: string, error: string): void {
  trackEvent('oqf_validation_error', {
    stepId,
    error,
    errorType: 'validation'
  });
}

export function trackBackClick(from: string, to: string): void {
  trackEvent('oqf_back_click', { from, to });
}

export function trackAbandon(stepId: string): void {
  trackEvent('oqf_abandon', {
    stepId,
    answersCount: funnelTracker.getSteps().length,
    completionRate: 1 - funnelTracker.getDropoffRate()
  });
}

export function trackComplete(totalSteps: number, duration: number): void {
  trackEvent('oqf_complete', {
    totalSteps,
    duration,
    completionRate: 1.0
  });
}

export function trackResultSuccess(planId: string): void {
  trackEvent('oqf_result_success', { planId });
}

export function trackResultError(error: string): void {
  trackEvent('oqf_result_error', { 
    error,
    errorType: 'generation'
  });
}

// Performance monitoring
export class PerformanceMonitor {
  private marks: Map<string, number> = new Map();
  
  mark(name: string): void {
    this.marks.set(name, performance.now());
  }
  
  measure(name: string, startMark: string, endMark?: string): number | null {
    const start = this.marks.get(startMark);
    const end = endMark ? this.marks.get(endMark) : performance.now();
    
    if (start === undefined || end === undefined) {
      return null;
    }
    
    const duration = end - start;
    
    // Track as performance event
    trackEvent('oqf_view' as PlanBuilderEvent, {
      stepId: name,
      duration: Math.round(duration)
    });
    
    return duration;
  }
  
  clear(): void {
    this.marks.clear();
  }
}

export const performanceMonitor = new PerformanceMonitor();

// Export a ready-to-use instance
export const planBuilderTelemetry = {
  trackEvent,
  trackFlowStart,
  trackStepView,
  trackAnswerSubmit,
  trackValidationError,
  trackBackClick,
  trackAbandon,
  trackComplete,
  trackResultSuccess,
  trackResultError,
  funnelTracker,
  performanceMonitor
};







