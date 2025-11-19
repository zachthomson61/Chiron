import { useEffect, useState } from 'react';

// Feature flag configuration
export const FEATURE_FLAGS = {
  plan_builder_oqf: {
    name: 'One Question Flow for Plan Builder',
    description: 'New stepped plan builder with one question per screen',
    defaultValue: false,
    environments: {
      development: true,
      staging: true,
      production: false
    }
  },
  // Add more feature flags here
} as const;

export type FeatureFlagKey = keyof typeof FEATURE_FLAGS;

// Get current environment
function getCurrentEnvironment(): 'development' | 'staging' | 'production' {
  if (typeof window === 'undefined') return 'production';
  
  const hostname = window.location.hostname;
  
  if (hostname === 'localhost' || hostname === '127.0.0.1') {
    return 'development';
  }
  
  if (hostname.includes('staging') || hostname.includes('preview')) {
    return 'staging';
  }
  
  return 'production';
}

// Check if a feature flag is enabled
function isFeatureEnabled(flagKey: FeatureFlagKey): boolean {
  const flag = FEATURE_FLAGS[flagKey];
  if (!flag) return false;
  
  // Check localStorage override first
  if (typeof window !== 'undefined') {
    const override = localStorage.getItem(`feature_flag_${flagKey}`);
    if (override !== null) {
      return override === 'true';
    }
  }
  
  // Check environment-specific setting
  const environment = getCurrentEnvironment();
  if (flag.environments && flag.environments[environment] !== undefined) {
    return flag.environments[environment];
  }
  
  // Fall back to default value
  return flag.defaultValue;
}

// Hook to use a feature flag
export function useFeatureFlag(flagKey: FeatureFlagKey): boolean {
  const [enabled, setEnabled] = useState(() => isFeatureEnabled(flagKey));

  useEffect(() => {
    // Listen for localStorage changes
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === `feature_flag_${flagKey}`) {
        setEnabled(isFeatureEnabled(flagKey));
      }
    };

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, [flagKey]);

  return enabled;
}

// Hook to manage all feature flags (for admin panel)
export function useFeatureFlags() {
  const [flags, setFlags] = useState<Record<FeatureFlagKey, boolean>>(() => {
    const result = {} as Record<FeatureFlagKey, boolean>;
    for (const key in FEATURE_FLAGS) {
      result[key as FeatureFlagKey] = isFeatureEnabled(key as FeatureFlagKey);
    }
    return result;
  });

  const toggleFlag = (flagKey: FeatureFlagKey) => {
    const newValue = !flags[flagKey];
    localStorage.setItem(`feature_flag_${flagKey}`, String(newValue));
    setFlags(prev => ({ ...prev, [flagKey]: newValue }));
    
    // Dispatch storage event for other tabs
    window.dispatchEvent(new StorageEvent('storage', {
      key: `feature_flag_${flagKey}`,
      newValue: String(newValue),
      url: window.location.href
    }));
  };

  const resetFlag = (flagKey: FeatureFlagKey) => {
    localStorage.removeItem(`feature_flag_${flagKey}`);
    const defaultValue = isFeatureEnabled(flagKey);
    setFlags(prev => ({ ...prev, [flagKey]: defaultValue }));
    
    // Dispatch storage event for other tabs
    window.dispatchEvent(new StorageEvent('storage', {
      key: `feature_flag_${flagKey}`,
      newValue: null,
      url: window.location.href
    }));
  };

  const resetAll = () => {
    for (const key in FEATURE_FLAGS) {
      localStorage.removeItem(`feature_flag_${key}`);
    }
    
    // Refresh all flags
    const result = {} as Record<FeatureFlagKey, boolean>;
    for (const key in FEATURE_FLAGS) {
      result[key as FeatureFlagKey] = isFeatureEnabled(key as FeatureFlagKey);
    }
    setFlags(result);
  };

  return {
    flags,
    toggleFlag,
    resetFlag,
    resetAll,
    environment: getCurrentEnvironment()
  };
}

// Server-side feature flag check
export function checkFeatureFlag(
  flagKey: FeatureFlagKey,
  environment?: 'development' | 'staging' | 'production'
): boolean {
  const flag = FEATURE_FLAGS[flagKey];
  if (!flag) return false;
  
  const env = environment || 'production';
  
  if (flag.environments && flag.environments[env] !== undefined) {
    return flag.environments[env];
  }
  
  return flag.defaultValue;
}








