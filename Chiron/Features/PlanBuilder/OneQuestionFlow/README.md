# One Question Flow (OQF) - Plan Builder

## Overview

The One Question Flow is a SwiftUI implementation that presents one question per screen, improving completion rates through clear progression and adaptive branching.

## Features

- ✅ One question per screen (no scrolling)
- ✅ Adaptive branching based on answers
- ✅ Progress persistence (auto-saves to UserDefaults)
- ✅ Back navigation preserves answers
- ✅ Feature flag gating for safe rollout
- ✅ Mobile-optimized UI with 44px+ touch targets
- ✅ Smooth animations and transitions

## How to Enable

### Option 1: App Storage (Recommended)

The feature flag is controlled by `@AppStorage("planBuilderOQFEnabled")`. To enable:

1. **In Settings/Developer Menu:**
   ```swift
   UserDefaults.standard.set(true, forKey: "planBuilderOQFEnabled")
   ```

2. **Or add a toggle in your app:**
   ```swift
   @AppStorage("planBuilderOQFEnabled") var isOQFEnabled = false
   ```

### Option 2: Force Enable (Testing)

Temporarily modify `PlanBuilderView.swift`:
```swift
@AppStorage("planBuilderOQFEnabled") private var isOQFEnabled = true // Force enable
```

## Architecture

### Files Structure

```
OneQuestionFlow/
├── FlowConfig.swift          # Step definitions and branching logic
├── OQFViewModel.swift        # State management and persistence
├── OneQuestionShellView.swift # Main UI container
├── InputViews.swift          # Individual input components
└── README.md                 # This file
```

### Flow Steps

The flow includes 20 steps:
1. Plan Name
2. Primary Goal (branches to cardio/sport/experience)
3. Cardio Preference (conditional)
4. Sport Type (conditional)
5. Experience Level (branches to tutorial for beginners)
6. Tutorial Interest (conditional)
7. Days Per Week (branches to time check if ≤3)
8. Time Limited Check (conditional)
9. Session Duration / Session Duration Short
10. Target Muscles
11. Workout Split (branches to custom split design)
12. Custom Split Design (conditional)
13. Equipment Available
14. Injury Check (branches to injury details)
15. Injury Details (conditional)
16. Exercise Variety
17. Supersets
18. Program Duration
19. Start Date (branches to custom date)
20. Custom Start Date (conditional)

### State Management

- **Persistence**: Auto-saves to UserDefaults on every answer
- **State**: Tracks current step, answers, history, and timestamps
- **Navigation**: History stack for back navigation

## Customization

### Adding New Steps

1. Add a new `StepId` case in `FlowConfig.swift`
2. Create a `FlowStep` with your question configuration
3. Add it to the `steps` dictionary
4. Update branching logic in previous steps

### Modifying Branching

Edit the `next` closure in any `FlowStep`:
```swift
next: { answer, answers in
    if answer == "some_value" {
        return .someStep
    }
    return .defaultStep
}
```

### Custom Validation

Add validation to any step:
```swift
validate: { answer in
    guard let value = answer as? String else {
        return "Invalid input"
    }
    if value.count < 3 {
        return "Must be at least 3 characters"
    }
    return nil // nil means valid
}
```

## Testing

### Manual Testing Checklist

- [ ] Complete happy path (minimal steps)
- [ ] Test all branching paths
- [ ] Validate error handling
- [ ] Test back navigation preserves answers
- [ ] Verify progress persistence across app restart
- [ ] Check mobile responsiveness
- [ ] Test keyboard navigation (if applicable)

### Debugging

Enable debug logging:
```swift
// In OQFViewModel.swift, add print statements:
print("DEBUG: Current step: \(currentStepId)")
print("DEBUG: Answers: \(answers)")
print("DEBUG: History: \(history)")
```

## Performance

- **State Persistence**: Debounced to 0.5s after changes
- **Animations**: Smooth transitions between steps
- **Memory**: Minimal - only stores answers and step IDs

## Future Enhancements

- [ ] Analytics tracking integration
- [ ] Edit answers from result screen
- [ ] Progress indicators with estimated time
- [ ] Voice input support
- [ ] Accessibility improvements (VoiceOver, Dynamic Type)

## Troubleshooting

### Feature Flag Not Working

- Check `UserDefaults` key matches: `planBuilderOQFEnabled`
- Verify `@AppStorage` is properly initialized
- Try force enabling in code

### Progress Not Saving

- Check UserDefaults permissions
- Verify JSON serialization is working
- Check console for encoding errors

### Branching Not Working

- Verify `next` closure logic
- Check answer types match expectations
- Add debug prints to see answer values

## License

Internal use only - Proprietary





