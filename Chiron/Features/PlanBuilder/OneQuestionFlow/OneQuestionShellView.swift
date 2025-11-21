import SwiftUI

// MARK: - One Question Shell View

/// Interactive “one question at a time” builder flow.
/// The optional callback lets the host view collapse the flow once the generated plan preview closes.
struct OneQuestionShellView: View {
    @ObservedObject var viewModel: OQFViewModel
    let onExitToPlans: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var planStore: PlanStore
    @State private var showExitConfirmation = false
    @State private var showPlanPreview = false
    @State private var isGeneratingPlan = false
    @State private var generatedPreviewPlan: TrainingPlan?
    
    init(viewModel: OQFViewModel, onExitToPlans: (() -> Void)? = nil) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onExitToPlans = onExitToPlans
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.planBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress Bar (hidden once we reach result / generating plan)
                if !viewModel.isAtResult && !showPlanPreview {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 2)
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.primaryPurple, Color.secondaryPurple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * viewModel.progress, height: 2)
                        }
                    }
                    .frame(height: 2)
                }
                
                // Header
                HStack {
                    if viewModel.currentStepId == .planName {
                        Color.clear
                            .frame(width: 44, height: 44)
                    } else {
                        Button(action: {
                            viewModel.goBack()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .foregroundColor(.planTextPrimary)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(!viewModel.canGoBack)
                        .opacity(viewModel.canGoBack ? 1.0 : 0.3)
                    }

                    Spacer()

                    // Exit Button
                    Button(action: {
                        showExitConfirmation = true
                    }) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.planTextPrimary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Question Content / Generate & Navigate on Result
                if viewModel.isAtResult {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            generateAndNavigateToPreview()
                        }
                } else if let step = viewModel.currentStep {
                    QuestionContentView(
                        step: step,
                        answer: viewModel.answers[step.id.rawValue],
                        validationError: viewModel.validationError,
                        onSubmit: { answer in
                            _ = viewModel.submitAnswer(answer)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    // Loading or error state
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.planTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showPlanPreview) {
            if let plan = generatedPreviewPlan {
                PlanPreviewView(plan: plan, source: .builder, onExit: onExitToPlans)
            }
        }
        .alert("Leave Plan Builder?", isPresented: $showExitConfirmation) {
            Button("Stay", role: .cancel) { }
            Button("Leave", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Your progress has been saved. You can continue where you left off anytime.")
        }
    }
}

// MARK: - Question Content View

struct QuestionContentView: View {
    let step: FlowStep
    let answer: Any?
    let validationError: String?
    let onSubmit: (Any) -> Void
    
    @State private var currentAnswer: Any?
    @State private var isSubmitting = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question Card
                VStack(alignment: .leading, spacing: 16) {
                    // Question Text
                    Text(step.prompt)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.planTextPrimary)
                        .multilineTextAlignment(.leading)
                    
                    // Helper Text
                    if let helper = step.helper {
                        Text(helper)
                            .font(.subheadline)
                            .foregroundColor(.planTextSecondary)
                    }
                    
                    // Input Control
                    inputControl
                        .padding(.top, 8)
                    
                    // Validation Error
                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                    
                    // Continue Button
                    Button(action: {
                        submitAnswer()
                    }) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Continue")
                                    .fontWeight(.semibold)
                            }
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(canSubmit ? Color.primaryPurple : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(28)
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .padding(.top, 16)
                    
                    // Skip Button (if optional)
                    if !step.required {
                        Button(action: {
                            submitAnswer()
                        }) {
                            Text("Skip this question")
                                .font(.subheadline)
                                .foregroundColor(.planTextSecondary)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(24)
                .background(Color.planCardBackground)
                .cornerRadius(20)
                .padding(.horizontal)
                .padding(.top, 24)
            }
        }
        .onAppear {
            currentAnswer = answer
        }
    }
    
    @ViewBuilder
    private var inputControl: some View {
        switch step.type {
        case .singleChoice:
            VStack(alignment: .leading, spacing: 12) {
                SingleChoiceView(
                    options: step.options ?? [],
                    selected: currentAnswer as? String,
                    onSelect: { currentAnswer = $0 }
                )
                
                if step.id == .workoutSplit, (currentAnswer as? String) == WorkoutSplit.custom.rawValue {
                    // Inline week planner for the Custom split choice
                    InlineCustomSplitPlanner()
                }
            }
            
        case .multiChoice:
            if step.id == .targetMuscles {
                // Use icon grid with 3 columns for muscle groups
                let selectedStrings = (currentAnswer as? [String]) ?? []
                let selectedSet = Set(selectedStrings.compactMap { MuscleGroup(rawValue: $0) })
                VStack(alignment: .leading, spacing: 12) {
                    let isAllSelected = selectedSet.count == MuscleGroup.allCases.count
                    HStack {
                        Button(action: {
                            if isAllSelected {
                                currentAnswer = []
                            } else {
                                currentAnswer = MuscleGroup.allCases.map { $0.rawValue }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isAllSelected ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundColor(.planAccent)
                                Text(isAllSelected ? "Deselect All" : "Select All")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.planTextPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.planCardBackground)
                            .cornerRadius(16)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                    
                    MuscleGroupGrid(
                        muscles: MuscleGroup.allCases,
                        selected: selectedSet,
                        onToggle: { muscle in
                            var strings = (currentAnswer as? [String]) ?? []
                            if let idx = strings.firstIndex(of: muscle.rawValue) {
                                strings.remove(at: idx)
                            } else {
                                strings.append(muscle.rawValue)
                            }
                            currentAnswer = strings
                        }
                    )
                }
            } else {
                MultiChoiceView(
                    options: step.options ?? [],
                    selected: (currentAnswer as? [String]) ?? [],
                    onToggle: { value in
                        var selected = (currentAnswer as? [String]) ?? []
                        if selected.contains(value) {
                            selected.removeAll { $0 == value }
                        } else {
                            selected.append(value)
                        }
                        currentAnswer = selected
                    }
                )
            }
            
        case .number:
            NumberInputView(
                value: currentAnswer as? Int ?? Int(step.min ?? 0),
                min: Int(step.min ?? 0),
                max: Int(step.max ?? 100),
                onValueChange: { currentAnswer = $0 }
            )
            
        case .range:
            RangeSliderView(
                value: {
                    // Handle both Int and Double answers
                    if let intValue = currentAnswer as? Int {
                        return Double(intValue)
                    } else if let doubleValue = currentAnswer as? Double {
                        return doubleValue
                    }
                    return step.min ?? 0
                }(),
                min: step.min ?? 0,
                max: step.max ?? 100,
                step: step.step ?? 1,
                unit: step.unit ?? "",
                onValueChange: { value in
                    // Convert to Int if step has no decimals
                    if step.step == 1.0 || step.step == nil {
                        currentAnswer = Int(value)
                    } else {
                        currentAnswer = value
                    }
                }
            )
            
        case .chips:
            ChipSelectView(
                options: step.options ?? [],
                selected: (currentAnswer as? [String]) ?? [],
                onToggle: { value in
                    var selected = (currentAnswer as? [String]) ?? []
                    if selected.contains(value) {
                        selected.removeAll { $0 == value }
                    } else {
                        selected.append(value)
                    }
                    currentAnswer = selected
                }
            )
            
        case .yesNo:
            YesNoToggleView(
                value: currentAnswer as? Bool,
                onSelect: { currentAnswer = $0 }
            )
            
        case .time:
            TimeInputView(
                value: currentAnswer as? String ?? "00:00",
                onValueChange: { currentAnswer = $0 }
            )
            
        case .text:
            TextInputView(
                text: (currentAnswer as? String) ?? "",
                placeholder: step.placeholder ?? "",
                onTextChange: { currentAnswer = $0 }
            )
        }
    }
    
    private var canSubmit: Bool {
        if !step.required {
            return true
        }
        return currentAnswer != nil
    }
    
    private func submitAnswer() {
        let answer: Any
        if let current = currentAnswer {
            answer = current
        } else if !step.required {
            answer = "" // Empty string for optional skipped questions
        } else {
            return // Can't submit without answer for required questions
        }
        
        isSubmitting = true
        onSubmit(answer)
        // Reset after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSubmitting = false
        }
    }
}

// MARK: - Generation & Navigation
extension OneQuestionShellView {
    private func generateAndNavigateToPreview() {
        // Avoid duplicate navigation and concurrent generation
        guard !showPlanPreview, !isGeneratingPlan else { return }
        isGeneratingPlan = true
        Task {
            // Build input from answers
            guard let input = await viewModel.generatePlan() else {
                await MainActor.run {
                    isGeneratingPlan = false
                }
                return
            }

            // Use existing PlanBuilderViewModel pipeline to generate plan
            let builderVM = PlanBuilderViewModel()
            builderVM.input = input
            await builderVM.generatePlan()
            guard let plan = builderVM.generatedPlan else {
                await MainActor.run {
                    isGeneratingPlan = false
                }
                return
            }

            planStore.addPlan(plan)

            await MainActor.run {
                generatedPreviewPlan = plan
                showPlanPreview = true
                isGeneratingPlan = false
            }
        }
    }
}

// MARK: - Result View

struct ResultView: View {
    @ObservedObject var viewModel: OQFViewModel
    @EnvironmentObject private var planStore: PlanStore
    @State private var generatedPlan: TrainingPlan?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isGenerating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Creating Your Plan...")
                            .font(.headline)
                            .foregroundColor(.planTextPrimary)
                        Text("This usually takes 10-15 seconds")
                            .font(.subheadline)
                            .foregroundColor(.planTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if let plan = generatedPlan {
                    PlanSummaryView(plan: plan, answers: viewModel.answers)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Generation Failed")
                            .font(.headline)
                            .foregroundColor(.planTextPrimary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.planTextSecondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            generatePlan()
                        }
                        .buttonStyle(PlanButtonStyle(isPrimary: true))
                        .padding(.top, 8)
                    }
                    .padding(40)
                }
            }
            .padding()
        }
        .onAppear {
            if generatedPlan == nil && !isGenerating {
                generatePlan()
            }
        }
    }
    
    private func generatePlan() {
        isGenerating = true
        errorMessage = nil
        
        Task {
            guard let input = await viewModel.generatePlan() else {
                errorMessage = "Failed to convert answers to plan input"
                isGenerating = false
                return
            }
            
            // Use existing PlanBuilderViewModel to generate
            let planViewModel = PlanBuilderViewModel()
            planViewModel.input = input
            
            await planViewModel.generatePlan()
            
            if let plan = planViewModel.generatedPlan {
                generatedPlan = plan
                planStore.addPlan(plan)
            } else {
                errorMessage = planViewModel.errorMessage ?? "Failed to generate plan"
            }
            
            isGenerating = false
        }
    }
}

// MARK: - Plan Summary View

struct PlanSummaryView: View {
    let plan: TrainingPlan
    let answers: [String: Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your Training Plan")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.planTextPrimary)
            
            Text(plan.name)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.planAccent)
            
            // Plan details
            VStack(alignment: .leading, spacing: 12) {
                Label("\(plan.daysPerWeek) days per week", systemImage: "calendar")
                Label("\(plan.duration) weeks", systemImage: "clock")
                Label("\(plan.targetMuscles.count) muscle groups", systemImage: "figure.strengthtraining.traditional")
            }
            .font(.subheadline)
            .foregroundColor(.planTextSecondary)
            
            // Summary of answers
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Selections")
                    .font(.headline)
                    .foregroundColor(.planTextPrimary)
                
                ForEach(Array(answers.keys.prefix(6)), id: \.self) { key in
                    if let value = answers[key] {
                        AnswerSummaryRow(key: key, value: value)
                    }
                }
            }
            .padding()
            .background(Color.planCardBackground)
            .cornerRadius(16)
        }
        .padding()
    }
}

struct AnswerSummaryRow: View {
    let key: String
    let value: Any
    
    var body: some View {
        HStack {
            Text(formatKey(key))
                .font(.subheadline)
                .foregroundColor(.planTextSecondary)
            Spacer()
            Text(formatValue(value))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.planTextPrimary)
        }
    }
    
    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func formatValue(_ value: Any) -> String {
        if let string = value as? String {
            return string
        } else if let int = value as? Int {
            return "\(int)"
        } else if let bool = value as? Bool {
            return bool ? "Yes" : "No"
        } else if let array = value as? [String] {
            return array.joined(separator: ", ")
        }
        return "\(value)"
    }
}
