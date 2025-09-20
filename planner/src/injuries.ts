import type { Exercise, InjuryConstraint } from './types';

export function isAllowed(ex: Exercise, injuries: InjuryConstraint[]): boolean {
  for (const inj of injuries) {
    switch (inj.tag) {
      case 'knee': {
        const kneePatterns = ['squat', 'lunge'] as const;
        if (inj.severity === 'avoid') {
          if (kneePatterns.includes(ex.pattern as any) && !ex.flags.includes('knee_friendly')) return false;
        }
        // modify handled downstream; allowed here
        break;
      }
      case 'shoulder': {
        if (inj.severity === 'avoid') {
          if (ex.pattern === 'push_v' && !ex.flags.includes('shoulder_friendly')) return false;
        }
        break;
      }
      case 'low_back': {
        if (inj.severity === 'avoid') {
          if (ex.pattern === 'hinge' && !ex.flags.includes('spine_friendly')) return false;
        }
        break;
      }
      case 'hip': {
        if (inj.severity === 'avoid') {
          if ((ex.pattern === 'lunge' || ex.pattern === 'squat') && !ex.flags.includes('knee_friendly')) return false;
        }
        break;
      }
      case 'ankle': {
        // allow most but avoid ballistic lower movements unless flagged time_efficient
        break;
      }
      case 'elbow':
      case 'wrist':
      case 'neck':
        // handled via selection bias; not strict exclusion here
        break;
    }
  }
  return true;
}

export function modifiedSchemePenalty(pattern: Exercise['pattern'], injuries: InjuryConstraint[]): number {
  // reduce sets by 1 for modify severity on matching pattern
  for (const inj of injuries) {
    if (inj.severity !== 'modify') continue;
    if (inj.tag === 'knee' && (pattern === 'squat' || pattern === 'lunge')) return 1;
    if (inj.tag === 'shoulder' && pattern === 'push_v') return 1;
    if (inj.tag === 'low_back' && pattern === 'hinge') return 1;
  }
  return 0;
}




