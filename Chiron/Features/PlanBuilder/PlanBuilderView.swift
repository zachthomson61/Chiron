import SwiftUI

struct PlanBuilderView: View {
    @StateObject private var viewModel = PlanBuilderViewModel()
    @StateObject private var oqfViewModel = OQFViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var planStore: PlanStore
    @State private var showingPreview = false
    @AppStorage("planBuilderOQFEnabled") private var isOQFEnabled = true  // Enable One Question Flow
    
    // Custom Split State
    @State private var customSplitSelectedDayIndex: Int = 0
    @State private var customSplitIntents: [DayIntent] = []
    @State private var customSplitSpecs: [Int: CustomDaySpec] = [:]
    
    var body: some View {
        // Feature flag: Show One Question Flow if enabled
        if isOQFEnabled {
            OneQuestionShellView(viewModel: oqfViewModel)
                .environmentObject(planStore)
                .onAppear {
                    oqfViewModel.reset()
                }
        } else {
            legacyPlanBuilderView
        }
    }
    
    // MARK: - Legacy Plan Builder View
    
    private var legacyPlanBuilderView: some View {
        ZStack {
            // Background
            Color.planBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Scrollable form content
                ScrollView {
                    VStack(spacing: 24) {
                        // Plan Name Section
                        nameSection
                        
                        // Goals Section
                        goalsSection
                        
                        // Schedule Section
                        scheduleSection
                        
                        // Target Muscles Section
                        targetMusclesSection
                        
                        // Split Section
                        splitSection
                        
                        // Injuries Section
                        injuriesSection
                        
                        // Variety Section
                        varietySection
                        
                        // Supersets Section
                        supersetsSection
                        
                        // Bottom padding for button
                        Color.clear.frame(height: 100)
                    }
                    .padding()
                }
                
                // Generate button pinned to bottom
                VStack {
                    Button(action: {
                        print("DEBUG: Create Training Plan button pressed")
                        print("DEBUG: Button state - canGeneratePlan: \(viewModel.canGeneratePlan), isGenerating: \(viewModel.isGenerating)")
                        Task {
                            print("DEBUG: About to call generatePlan")
                            await viewModel.generatePlan()
                            print("DEBUG: generatePlan call completed")
                            
                            // Save the plan if generation was successful
                            if let plan = viewModel.generatedPlan {
                                print("DEBUG: Saving plan to PlanStore")
                                planStore.addPlan(plan)
                            }
                        }
                    }) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .textPrimary))
                        } else {
                            Text("Create Training Plan")
                        }
                    }
                    .buttonStyle(PlanButtonStyle(isPrimary: true))
                    .disabled(!viewModel.canGeneratePlan || viewModel.isGenerating)
                    .opacity(viewModel.canGeneratePlan ? 1.0 : 0.6)
                    .onAppear {
                        print("DEBUG: Button appeared - canGeneratePlan: \(viewModel.canGeneratePlan), isGenerating: \(viewModel.isGenerating)")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .background(
                    Color.planBackground
                        .shadow(color: .primaryPurple.opacity(0.1), radius: 10, x: 0, y: -5)
                )
            }
        }
        .navigationTitle("Build Plan")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .navigationDestination(isPresented: $viewModel.navigateToPreview) {
            if let plan = viewModel.generatedPlan {
                PlanPreviewView(plan: plan)
            }
        }
    }
    
    // MARK: - Section Views
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanSectionHeader(title: "Plan Name")
            
            TextField("Enter plan name", text: $viewModel.input.name)
                .font(.body)
                .foregroundColor(.planTextPrimary)
                .padding()
                .background(Color.planCardBackground)
                .cornerRadius(12)
        }
        .planSectionStyle()
    }
    
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanSectionHeader(
                title: "Goals",
                subtitle: "What do you want to achieve?"
            )
            
            PlanChipGrid(
                items: FocusArea.allCases,
                selected: Set(viewModel.input.goals),
                label: { $0.rawValue },
                icon: { $0.icon },
                onToggle: viewModel.toggleGoal
            )
        }
        .planSectionStyle()
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanSectionHeader(
                title: "Schedule",
                subtitle: "How often can you train?"
            )
            
            // Days per week
            PlanSlider(
                title: "Days Per Week",
                value: Binding(
                    get: { Double(viewModel.input.daysPerWeek) },
                    set: { viewModel.input.daysPerWeek = Int($0) }
                ),
                range: 1...7,
                step: 1,
                format: "%d days"
            )
            
            // Session duration
            PlanSlider(
                title: "Session Duration",
                value: Binding(
                    get: { Double(viewModel.input.sessionMinutes) },
                    set: { newValue in
                        // Round to nearest step (5 minutes)
                        let rounded = round(newValue / 5.0) * 5.0
                        viewModel.input.sessionMinutes = Int(rounded)
                    }
                ),
                range: 15...120,
                step: 5,
                format: "%d min"
            )
            
            // Program duration
            PlanSlider(
                title: "Program Duration",
                value: Binding(
                    get: { Double(viewModel.input.programDuration) },
                    set: { viewModel.input.programDuration = Int($0) }
                ),
                range: 1...24,
                step: 1,
                format: "%d weeks"
            )
        }
        .planCardStyle()
        .planSectionStyle()
    }
    
    
    private var targetMusclesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanSectionHeader(
                title: "Target Muscles",
                subtitle: "Pick the muscle groups you want to train:"
            )
            
            MuscleGroupGrid(
                muscles: MuscleGroup.allCases,
                selected: Set(viewModel.input.targetMuscles),
                onToggle: viewModel.toggleTargetMuscle
            )
        }
        .planCardStyle()
        .planSectionStyle()
    }
    
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanSectionHeader(
                title: "Workout Split",
                subtitle: "How to organize your training"
            )
            
            LazyVStack(spacing: 12) {
                ForEach(WorkoutSplit.allCases, id: \.self) { split in
                    Button(action: {
                        viewModel.input.split = split
                        if split == .custom {
                            initializeCustomSplit()
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(split.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.planTextPrimary)
                                Text(split.description)
                                    .font(.caption)
                                    .foregroundColor(.planTextSecondary)
                            }
                            Spacer()
                            if viewModel.input.split == split {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.planAccent)
                            }
                        }
                        .padding()
                        .background(
                            viewModel.input.split == split ?
                            Color.planCardBackgroundSelected :
                            Color.planCardBackground
                        )
                        .cornerRadius(12)
                    }
                }
            }
            
            // Inline Custom Split Configuration
            if viewModel.input.split == .custom {
                customSplitConfiguration
            }
        }
        .planSectionStyle()
    }
    
    private var injuriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanSectionHeader(
                title: "Injuries",
                subtitle: "Any injuries or body parts bugging you?"
            )
            
            // Text input with Add button
            HStack(spacing: 12) {
                TextField("Type here...", text: $viewModel.currentInjuryEntry)
                    .font(.body)
                    .foregroundColor(.planTextPrimary)
                    .padding()
                    .background(Color.planCardBackground)
                    .cornerRadius(12)
                    .onSubmit {
                        viewModel.addCurrentInjuryEntry()
                    }
                
                if !viewModel.currentInjuryEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Add") {
                        viewModel.addCurrentInjuryEntry()
                    }
                    .buttonStyle(PlanButtonStyle(isPrimary: true))
                    .frame(width: 60)
                }
            }
            
            // Token chips
            TokenField(
                tokens: viewModel.input.injuryNotes,
                onRemove: viewModel.removeInjuryNote
            )
            
            // Constraint preview
            if !viewModel.input.injuryNotes.isEmpty {
                Text(viewModel.detectedConstraintsText)
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
                    .padding(.top, 4)
            }
        }
        .planCardStyle()
        .planSectionStyle()
    }
    
    private var varietySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanSectionHeader(
                title: "Exercise Variety",
                subtitle: "How much variety do you want?"
            )
            
            VStack(spacing: 16) {
                // Slider
                Slider(
                    value: Binding(
                        get: { viewModel.input.varietyContinuum },
                        set: { viewModel.input.varietyContinuum = $0.clamped(to: 0...1) }
                    ),
                    in: 0...1,
                    step: 0.01
                )
                .tint(.planAccent)
                
                // Labels
                HStack {
                    Text("Consistent")
                        .font(.caption)
                        .foregroundColor(.planTextSecondary)
                    Spacer()
                    Text("Balanced")
                        .font(.caption)
                        .foregroundColor(.planTextSecondary)
                    Spacer()
                    Text("Varied")
                        .font(.caption)
                        .foregroundColor(.planTextSecondary)
                }
                
                // Dynamic description
                Text(viewModel.input.varietyContinuum.band.description)
                    .font(.footnote)
                    .foregroundColor(.planTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.planCardBackground)
            .cornerRadius(12)
        }
        .planSectionStyle()
    }
    
    private var supersetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanToggle(
                title: "Include Supersets",
                subtitle: "Pair exercises for efficiency",
                isOn: $viewModel.input.supersets
            )
            .padding()
            .background(Color.planCardBackground)
            .cornerRadius(12)
        }
        .planSectionStyle()
    }
    
    // MARK: - Custom Split Configuration
    
    private var customSplitConfiguration: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider()
                .background(Color.planAccent.opacity(0.3))
                .padding(.vertical, 8)
            
            // Instructions
            Text("Customize each training day")
                .font(.subheadline)
                .foregroundColor(.planTextSecondary)
                .padding(.bottom, 4)
            
            // Day Pills - Horizontal scrollable selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<viewModel.input.daysPerWeek, id: \.self) { index in
                        Button(action: {
                            customSplitSelectedDayIndex = index
                        }) {
                            VStack(spacing: 4) {
                                Text("Day \(index + 1)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(customSplitSelectedDayIndex == index ? .textPrimary : .planTextPrimary)
                                
                                // Show selected intent below day number
                                if index < customSplitIntents.count {
                                    Text(customSplitIntents[index].rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.planTextSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(customSplitSelectedDayIndex == index ? Color.planAccent : Color.planCardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(customSplitSelectedDayIndex == index ? Color.clear : Color.planAccent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.bottom, 8)
            
            // Intent Selection for Selected Day
            VStack(alignment: .leading, spacing: 12) {
                Text("Day \(customSplitSelectedDayIndex + 1) Focus")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.planTextPrimary)
                
                Text("What type of workout is this?")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
                
                // Intent Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(DayIntent.allCases, id: \.self) { intent in
                        Button(action: {
                            setCurrentDayIntent(intent)
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(intent.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.planTextPrimary)
                                    .multilineTextAlignment(.leading)
                                
                                Text(intent.description)
                                    .font(.caption)
                                    .foregroundColor(.planTextSecondary)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                                
                                if currentDayIntent == intent {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.planAccent)
                                            .font(.title3)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 100)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(currentDayIntent == intent ? Color.planCardBackgroundSelected : Color.planCardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(currentDayIntent == intent ? Color.planAccent : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.top, 8)
            
            // Custom Muscles Selection (if Custom Muscles is selected)
            if currentDayIntent == .customMuscles {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(Color.planAccent.opacity(0.3))
                        .padding(.vertical, 8)
                    
                    PlanSectionHeader(
                        title: "Select Muscles",
                        subtitle: "Choose the muscle groups for this day"
                    )
                    
                    MuscleGroupGrid(
                        muscles: MuscleGroup.allCases,
                        selected: currentDayCustomMuscles,
                        onToggle: toggleCustomMuscle
                    )
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.planCardBackground.opacity(0.5))
        .cornerRadius(16)
        .padding(.top, 12)
    }
    
    // MARK: - Custom Split Computed Properties
    
    private var currentDayIntent: DayIntent {
        guard customSplitSelectedDayIndex < customSplitIntents.count else { return .fullBody }
        return customSplitIntents[customSplitSelectedDayIndex]
    }
    
    private var currentDayCustomMuscles: Set<MuscleGroup> {
        customSplitSpecs[customSplitSelectedDayIndex]?.muscles ?? []
    }
    
    // MARK: - Custom Split Methods
    
    private func initializeCustomSplit() {
        // Initialize intents array with smart defaults based on days per week
        let days = viewModel.input.daysPerWeek
        
        switch days {
        case 3:
            customSplitIntents = [.push, .pull, .legs]
        case 4:
            customSplitIntents = [.upper, .lower, .push, .pull]
        case 5:
            customSplitIntents = [.push, .pull, .legs, .upper, .lower]
        case 6:
            customSplitIntents = [.push, .pull, .legs, .push, .pull, .legs]
        case 7:
            customSplitIntents = [.push, .pull, .legs, .upper, .lower, .arms, .fullBody]
        default:
            customSplitIntents = Array(repeating: .fullBody, count: days)
        }
        
        // Reset custom specs
        customSplitSpecs = [:]
        customSplitSelectedDayIndex = 0
        
        // Save to viewModel
        saveCustomSplit()
    }
    
    private func setCurrentDayIntent(_ intent: DayIntent) {
        guard customSplitSelectedDayIndex < customSplitIntents.count else { return }
        customSplitIntents[customSplitSelectedDayIndex] = intent
        
        // Clear custom specs if not custom muscles
        if intent != .customMuscles {
            customSplitSpecs.removeValue(forKey: customSplitSelectedDayIndex)
        }
        
        // Save to viewModel
        saveCustomSplit()
    }
    
    private func toggleCustomMuscle(_ muscle: MuscleGroup) {
        var muscles = currentDayCustomMuscles
        if muscles.contains(muscle) {
            muscles.remove(muscle)
        } else {
            muscles.insert(muscle)
        }
        customSplitSpecs[customSplitSelectedDayIndex] = CustomDaySpec(muscles: muscles)
        
        // Save to viewModel
        saveCustomSplit()
    }
    
    private func saveCustomSplit() {
        // Convert 0-based indices to 1-based for CustomSplit
        var oneBasedCustomSpecs: [Int: CustomDaySpec] = [:]
        for (zeroBasedIndex, spec) in customSplitSpecs {
            oneBasedCustomSpecs[zeroBasedIndex + 1] = spec
        }
        
        let customSplit = CustomSplit(
            dayIntents: customSplitIntents,
            customSpecs: oneBasedCustomSpecs
        )
        
        viewModel.input.customSplit = customSplit
    }
    
    // MARK: - Feature Flag Toggle (for testing)
    
    private var featureFlagToggle: some View {
        Button(action: {
            isOQFEnabled.toggle()
        }) {
            HStack {
                Image(systemName: isOQFEnabled ? "checkmark.circle.fill" : "circle")
                Text(isOQFEnabled ? "One Question Flow" : "Legacy Form")
            }
            .font(.caption)
            .foregroundColor(.planTextSecondary)
        }
    }
}
