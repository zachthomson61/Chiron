import SwiftUI

struct PlanBuilderView: View {
    @StateObject private var viewModel = PlanBuilderViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var planStore: PlanStore
    @State private var showingPreview = false
    @State private var showingCustomSplit = false
    
    var body: some View {
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
        .navigationDestination(isPresented: $showingCustomSplit) {
            CustomSplitView(input: viewModel.input) { customSplit in
                viewModel.input.customSplit = customSplit
                showingCustomSplit = false
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
                    set: { viewModel.input.sessionMinutes = Int($0) }
                ),
                range: 30...90,
                step: 15,
                format: "%d min"
            )
            
            // Program duration
            PlanSlider(
                title: "Program Duration",
                value: Binding(
                    get: { Double(viewModel.input.programDuration) },
                    set: { viewModel.input.programDuration = Int($0) }
                ),
                range: 2...16,
                step: 2,
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
                            showingCustomSplit = true
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
}
