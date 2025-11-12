import { flow, calculatePathLength } from '@/flow/config';

describe('Plan Builder Flow - Next Logic', () => {
  describe('Primary Goal Step', () => {
    it('should navigate to cardio_preference for fat_loss goal', () => {
      const step = flow.steps.primary_goal;
      const nextStep = step.next('fat_loss', {});
      expect(nextStep).toBe('cardio_preference');
    });

    it('should navigate to cardio_preference for endurance goal', () => {
      const step = flow.steps.primary_goal;
      const nextStep = step.next('endurance', {});
      expect(nextStep).toBe('cardio_preference');
    });

    it('should navigate to sport_type for athletic goal', () => {
      const step = flow.steps.primary_goal;
      const nextStep = step.next('athletic', {});
      expect(nextStep).toBe('sport_type');
    });

    it('should navigate to experience_level for other goals', () => {
      const step = flow.steps.primary_goal;
      expect(step.next('muscle_gain', {})).toBe('experience_level');
      expect(step.next('strength', {})).toBe('experience_level');
      expect(step.next('general', {})).toBe('experience_level');
    });
  });

  describe('Experience Level Step', () => {
    it('should navigate to tutorial_interest for beginners', () => {
      const step = flow.steps.experience_level;
      const nextStep = step.next('beginner', {});
      expect(nextStep).toBe('tutorial_interest');
    });

    it('should navigate to days_per_week for non-beginners', () => {
      const step = flow.steps.experience_level;
      expect(step.next('novice', {})).toBe('days_per_week');
      expect(step.next('intermediate', {})).toBe('days_per_week');
      expect(step.next('advanced', {})).toBe('days_per_week');
    });
  });

  describe('Days Per Week Step', () => {
    it('should navigate to time_limited_check for 3 or fewer days', () => {
      const step = flow.steps.days_per_week;
      expect(step.next(2, {})).toBe('time_limited_check');
      expect(step.next(3, {})).toBe('time_limited_check');
    });

    it('should navigate to session_duration for more than 3 days', () => {
      const step = flow.steps.days_per_week;
      expect(step.next(4, {})).toBe('session_duration');
      expect(step.next(5, {})).toBe('session_duration');
      expect(step.next(6, {})).toBe('session_duration');
      expect(step.next(7, {})).toBe('session_duration');
    });
  });

  describe('Time Limited Check Step', () => {
    it('should navigate to session_duration_short when time limited', () => {
      const step = flow.steps.time_limited_check;
      const nextStep = step.next(true, {});
      expect(nextStep).toBe('session_duration_short');
    });

    it('should navigate to session_duration when not time limited', () => {
      const step = flow.steps.time_limited_check;
      const nextStep = step.next(false, {});
      expect(nextStep).toBe('session_duration');
    });
  });

  describe('Workout Split Step', () => {
    it('should navigate to custom_split_design for custom split', () => {
      const step = flow.steps.workout_split;
      const nextStep = step.next('custom', {});
      expect(nextStep).toBe('custom_split_design');
    });

    it('should navigate to equipment_available for predefined splits', () => {
      const step = flow.steps.workout_split;
      expect(step.next('full_body', {})).toBe('equipment_available');
      expect(step.next('upper_lower', {})).toBe('equipment_available');
      expect(step.next('push_pull_legs', {})).toBe('equipment_available');
      expect(step.next('body_part', {})).toBe('equipment_available');
    });
  });

  describe('Injury Check Step', () => {
    it('should navigate to injury_details when injuries exist', () => {
      const step = flow.steps.injury_check;
      const nextStep = step.next(true, {});
      expect(nextStep).toBe('injury_details');
    });

    it('should navigate to exercise_variety when no injuries', () => {
      const step = flow.steps.injury_check;
      const nextStep = step.next(false, {});
      expect(nextStep).toBe('exercise_variety');
    });
  });

  describe('Start Date Step', () => {
    it('should navigate to custom_start_date for custom option', () => {
      const step = flow.steps.start_date;
      const nextStep = step.next('custom', {});
      expect(nextStep).toBe('custom_start_date');
    });

    it('should navigate to RESULT for predefined dates', () => {
      const step = flow.steps.start_date;
      expect(step.next('today', {})).toBe('RESULT');
      expect(step.next('tomorrow', {})).toBe('RESULT');
      expect(step.next('next_monday', {})).toBe('RESULT');
    });
  });

  describe('Custom Start Date Step', () => {
    it('should always navigate to RESULT', () => {
      const step = flow.steps.custom_start_date;
      const nextStep = step.next('2024-12-01', {});
      expect(nextStep).toBe('RESULT');
    });
  });
});

describe('Plan Builder Flow - Validation', () => {
  describe('Plan Name Validation', () => {
    const step = flow.steps.plan_name;

    it('should reject empty names', () => {
      expect(step.validate?.('')).toBe('Please enter a plan name');
      expect(step.validate?.('  ')).toBe('Please enter a plan name');
    });

    it('should reject names that are too short', () => {
      expect(step.validate?.('A')).toBe('Name must be at least 2 characters');
    });

    it('should reject names that are too long', () => {
      const longName = 'A'.repeat(51);
      expect(step.validate?.(longName)).toBe('Name must be less than 50 characters');
    });

    it('should accept valid names', () => {
      expect(step.validate?.('My Workout Plan')).toBeNull();
      expect(step.validate?.('Summer Strength')).toBeNull();
    });
  });

  describe('Days Per Week Validation', () => {
    const step = flow.steps.days_per_week;

    it('should reject less than 2 days', () => {
      expect(step.validate?.(1)).toBe('Minimum 2 days per week for effective training');
      expect(step.validate?.(0)).toBe('Minimum 2 days per week for effective training');
    });

    it('should reject more than 7 days', () => {
      expect(step.validate?.(8)).toBe('Maximum 7 days per week');
      expect(step.validate?.(10)).toBe('Maximum 7 days per week');
    });

    it('should accept valid day counts', () => {
      expect(step.validate?.(2)).toBeNull();
      expect(step.validate?.(4)).toBeNull();
      expect(step.validate?.(7)).toBeNull();
    });
  });

  describe('Target Muscles Validation', () => {
    const step = flow.steps.target_muscles;

    it('should reject fewer than 3 muscle groups', () => {
      expect(step.validate?.([])).toBe('Please select at least 3 muscle groups');
      expect(step.validate?.(['chest'])).toBe('Please select at least 3 muscle groups');
      expect(step.validate?.(['chest', 'back'])).toBe('Please select at least 3 muscle groups');
    });

    it('should accept 3 or more muscle groups', () => {
      expect(step.validate?.(['chest', 'back', 'legs'])).toBeNull();
      expect(step.validate?.(['chest', 'back', 'legs', 'shoulders'])).toBeNull();
    });
  });

  describe('Equipment Validation', () => {
    const step = flow.steps.equipment_available;

    it('should reject empty equipment selection', () => {
      expect(step.validate?.([])).toBe('Please select at least one option');
    });

    it('should accept any equipment selection', () => {
      expect(step.validate?.(['barbell'])).toBeNull();
      expect(step.validate?.(['bodyweight'])).toBeNull();
      expect(step.validate?.(['barbell', 'dumbbells', 'cables'])).toBeNull();
    });
  });

  describe('Custom Start Date Validation', () => {
    const step = flow.steps.custom_start_date;

    it('should reject invalid dates', () => {
      expect(step.validate?.('not-a-date')).toBe('Please enter a valid date');
      expect(step.validate?.('2024-13-01')).toBe('Please enter a valid date');
    });

    it('should reject past dates', () => {
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const dateStr = yesterday.toISOString().split('T')[0];
      expect(step.validate?.(dateStr)).toBe('Date cannot be in the past');
    });

    it('should accept valid future dates', () => {
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      const dateStr = tomorrow.toISOString().split('T')[0];
      expect(step.validate?.(dateStr)).toBeNull();
    });
  });
});

describe('Path Length Calculation', () => {
  it('should calculate correct path for minimal flow', () => {
    const answers = {
      plan_name: 'Test Plan',
      primary_goal: 'muscle_gain', // -> experience_level
      experience_level: 'intermediate', // -> days_per_week
      days_per_week: 4, // -> session_duration
      session_duration: 60, // -> target_muscles
      target_muscles: ['chest', 'back', 'legs'], // -> workout_split
      workout_split: 'full_body', // -> equipment_available
      equipment_available: ['barbell'], // -> injury_check
      injury_check: false, // -> exercise_variety
      exercise_variety: 'balanced', // -> supersets
      supersets: false, // -> program_duration
      program_duration: 8, // -> start_date
      start_date: 'today' // -> RESULT
    };

    const length = calculatePathLength(answers);
    expect(length).toBe(13);
  });

  it('should calculate correct path with conditional steps', () => {
    const answers = {
      plan_name: 'Test Plan',
      primary_goal: 'fat_loss', // -> cardio_preference
      cardio_preference: 'hiit', // -> experience_level
      experience_level: 'beginner', // -> tutorial_interest
      tutorial_interest: true, // -> days_per_week
      days_per_week: 3, // -> time_limited_check
      time_limited_check: true, // -> session_duration_short
      session_duration_short: 30, // -> target_muscles
      target_muscles: ['chest', 'back', 'legs'], // -> workout_split
      workout_split: 'custom', // -> custom_split_design
      custom_split_design: 'Day 1: Upper, Day 2: Lower', // -> equipment_available
      equipment_available: ['dumbbells'], // -> injury_check
      injury_check: true, // -> injury_details
      injury_details: 'Lower back pain', // -> exercise_variety
      exercise_variety: 'consistent', // -> supersets
      supersets: true, // -> program_duration
      program_duration: 12, // -> start_date
      start_date: 'custom', // -> custom_start_date
      custom_start_date: '2024-12-01' // -> RESULT
    };

    const length = calculatePathLength(answers);
    expect(length).toBe(19);
  });

  it('should handle empty answers', () => {
    const length = calculatePathLength({});
    expect(length).toBeGreaterThan(0);
    expect(length).toBeLessThanOrEqual(30); // Max safeguard
  });

  it('should prevent infinite loops', () => {
    // Even with circular references (shouldn't happen), it should terminate
    const answers = {};
    const length = calculatePathLength(answers);
    expect(length).toBeLessThanOrEqual(30);
  });
});





