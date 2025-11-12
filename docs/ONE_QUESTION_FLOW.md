# One Question Flow (OQF) - Plan Builder

## Overview
The One Question Flow (OQF) is a UX-optimized plan builder that presents one question per screen, improving completion rates through clear progression and adaptive branching.

## Architecture

### Core Components

#### 1. Flow Configuration (`/flow/config.ts`)
- Defines 20 steps with conditional branching logic
- Each step includes validation, next-step logic, and UI type
- Supports 8 input types: single, multi, number, range, chips, yesno, time, text

#### 2. State Management (`/hooks/usePlanFlow.ts`)
- Finite state machine for flow control
- Automatic localStorage persistence
- Server sync for authenticated users
- Progress calculation and history tracking

#### 3. UI Components
- **OneQuestionShell** (`/components/OneQuestionShell.tsx`): Main container with progress bar, navigation, and keyboard support
- **InputControls** (`/components/InputControls.tsx`): Reusable input components for each question type

#### 4. Telemetry (`/lib/telemetry/planBuilder.ts`)
- Comprehensive event tracking for funnel analysis
- Performance monitoring
- Server-side analytics aggregation

## Key Features

### Adaptive Branching
```typescript
// Example: Different paths based on goal
primary_goal: {
  next: (answer) => {
    if (answer === 'fat_loss') return 'cardio_preference';
    if (answer === 'athletic') return 'sport_type';
    return 'experience_level';
  }
}
```

### Progress Persistence
- Auto-saves to localStorage on every answer
- Server sync for authenticated users
- Resume from exact step on reload
- "Start over" option clears all data

### Mobile-First Design
- Minimum 44px touch targets
- Full-screen cards with no scrolling
- Swipe gestures support (optional)
- Responsive typography and spacing

### Keyboard Navigation
- **Enter**: Submit current answer
- **Arrow keys**: Navigate options (radio/checkbox)
- **Escape**: Exit flow with confirmation
- **Tab**: Standard focus navigation

## Implementation Guide

### 1. Database Setup
```bash
# Run Prisma migrations
npx prisma migrate dev --name add_plan_builder_oqf

# Generate Prisma client
npx prisma generate
```

### 2. Environment Variables
```env
DATABASE_URL="postgresql://..."
OPENAI_API_KEY="sk-..." # Optional for AI plan generation
```

### 3. Feature Flag Control
```typescript
// Enable in development
localStorage.setItem('feature_flag_plan_builder_oqf', 'true');

// Or use query parameter
/plan/builder?variant=oqf
```

### 4. Deploy Cloud Functions
```bash
# Deploy analytics endpoint
cd cloud-functions
./deploy.sh

# Deploy plan generation service
cd cloud-run-service
./deploy.sh
```

## Testing

### Unit Tests
```bash
npm test __tests__/flow.next.test.ts
```

### E2E Tests
```bash
npx playwright test e2e/oqf.spec.ts
```

### Manual Testing Checklist
- [ ] Complete happy path (minimal steps)
- [ ] Test all branching paths
- [ ] Validate error handling
- [ ] Test back navigation preserves answers
- [ ] Verify progress persistence across reload
- [ ] Check mobile responsiveness
- [ ] Test keyboard navigation
- [ ] Verify analytics events fire correctly

## Analytics & Metrics

### Key Events
- `oqf_start`: Flow initiated
- `oqf_step_view`: Step displayed
- `oqf_answer_submit`: Answer submitted
- `oqf_validation_error`: Validation failed
- `oqf_back_click`: Back navigation
- `oqf_abandon`: User left flow
- `oqf_complete`: Flow completed
- `oqf_result_success`: Plan generated successfully

### Funnel Metrics
Track conversion at each step:
```sql
SELECT 
  stepId,
  views,
  completions,
  (completions::float / views) as conversion_rate
FROM FunnelMetric
WHERE date = CURRENT_DATE
ORDER BY views DESC;
```

### Performance Targets
- **FCP**: < 1.5s
- **TTI**: < 2.5s on mid-tier mobile
- **Step transition**: < 300ms
- **Validation feedback**: < 100ms

## Rollout Strategy

### Phase 1: Internal Testing (Week 1)
- Deploy behind feature flag
- Internal team testing
- Fix critical bugs

### Phase 2: Beta Users (Week 2-3)
- 10% of new users
- A/B test vs legacy form
- Monitor completion rates

### Phase 3: Gradual Rollout (Week 4-6)
- Increase to 50%
- Monitor analytics dashboard
- Gather user feedback

### Phase 4: Full Launch
- 100% of users
- Remove legacy form
- Optimize based on data

## Troubleshooting

### Common Issues

#### Progress Not Saving
```javascript
// Check localStorage
console.log(localStorage.getItem('planBuilder:v2:anon'));

// Clear corrupted state
localStorage.removeItem('planBuilder:v2:anon');
```

#### Feature Flag Not Working
```javascript
// Force enable
window.localStorage.setItem('feature_flag_plan_builder_oqf', 'true');
location.reload();
```

#### Analytics Not Tracking
```javascript
// Check network tab for /api/analytics/track calls
// Verify events in browser console if in dev mode
```

## API Endpoints

### POST /api/plan/answers
Save incremental answers
```json
{
  "stepId": "primary_goal",
  "answer": "muscle_gain",
  "state": { /* optional full state */ }
}
```

### POST /api/plan/build
Generate plan from answers
```json
{
  "answers": {
    "plan_name": "My Plan",
    "primary_goal": "muscle_gain",
    // ... all answers
  }
}
```

### POST /api/plan/clear
Clear draft and start over
```json
{
  "userId": "user_123"
}
```

### POST /api/analytics/track
Track analytics events
```json
{
  "event": "oqf_step_view",
  "properties": {
    "stepId": "primary_goal",
    "sessionId": "oqf_12345"
  }
}
```

## Future Enhancements

### Short Term
- [ ] Add progress saving indicator
- [ ] Implement answer explanations ("Why we ask")
- [ ] Add voice input for accessibility
- [ ] Create admin dashboard for metrics

### Medium Term
- [ ] A/B test 2-questions-per-screen variant
- [ ] Add machine learning for smarter branching
- [ ] Implement collaborative planning (share with trainer)
- [ ] Add plan templates/presets

### Long Term
- [ ] Multi-language support
- [ ] AI-powered form completion assistance
- [ ] Integration with wearables for personalization
- [ ] Video tutorials for exercises

## Contact & Support

- **Tech Lead**: [Your Name]
- **Product Owner**: [PO Name]
- **Slack Channel**: #plan-builder-oqf
- **Documentation**: This file + inline code comments

## License
Internal use only - Proprietary





