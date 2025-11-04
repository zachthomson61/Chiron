import SwiftUI

// MARK: - Single Choice View

struct SingleChoiceView: View {
    let options: [QuestionOption]
    let selected: String?
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(options, id: \.value) { option in
                Button(action: {
                    onSelect(option.value)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.planTextPrimary)
                            
                            if let helper = option.helper {
                                Text(helper)
                                    .font(.caption)
                                    .foregroundColor(.planTextSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        if selected == option.value {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.primaryPurple)
                                .font(.title3)
                        } else {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .padding()
                    .background(
                        selected == option.value ?
                        Color.primaryPurple.opacity(0.1) :
                        Color.planCardBackground
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selected == option.value ?
                                Color.primaryPurple :
                                Color.clear,
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Multi Choice View

struct MultiChoiceView: View {
    let options: [QuestionOption]
    let selected: [String]
    let onToggle: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(options, id: \.value) { option in
                Button(action: {
                    onToggle(option.value)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.planTextPrimary)
                            
                            if let helper = option.helper {
                                Text(helper)
                                    .font(.caption)
                                    .foregroundColor(.planTextSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        if selected.contains(option.value) {
                            Image(systemName: "checkmark.square.fill")
                                .foregroundColor(.primaryPurple)
                                .font(.title3)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .padding()
                    .background(
                        selected.contains(option.value) ?
                        Color.primaryPurple.opacity(0.1) :
                        Color.planCardBackground
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if !selected.isEmpty {
                Text("\(selected.count) selected")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Number Input View

struct NumberInputView: View {
    @State var value: Int
    let min: Int
    let max: Int
    let onValueChange: (Int) -> Void
    
    var body: some View {
        HStack {
            Stepper("", value: $value, in: min...max)
                .onChange(of: value) {
                    onValueChange(value)
                }
            
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.planAccent)
                .frame(minWidth: 60)
        }
        .padding()
        .background(Color.planCardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Range Slider View

struct RangeSliderView: View {
    @State var value: Double
    let min: Double
    let max: Double
    let step: Double
    let unit: String
    let onValueChange: (Double) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Value Display
            Text("\(Int(value)) \(unit)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.planAccent)
            
            // Slider
            Slider(value: $value, in: min...max, step: step)
                .tint(.primaryPurple)
                .onChange(of: value) {
                    onValueChange(value)
                }
            
            // Min/Max Labels
            HStack {
                Text("\(Int(min)) \(unit)")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
                Spacer()
                Text("\(Int(max)) \(unit)")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
            }
        }
        .padding()
        .background(Color.planCardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Chip Select View

struct ChipSelectView: View {
    let options: [QuestionOption]
    let selected: [String]
    let onToggle: (String) -> Void
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
            ForEach(options, id: \.value) { option in
                Button(action: {
                    onToggle(option.value)
                }) {
                    Text(option.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(
                            selected.contains(option.value) ?
                            .white :
                            .planTextPrimary
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            selected.contains(option.value) ?
                            LinearGradient(
                                colors: [Color.primaryPurple, Color.secondaryPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Color.planCardBackground],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Yes/No Toggle View

struct YesNoToggleView: View {
    let value: Bool?
    let onSelect: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                onSelect(true)
            }) {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.headline)
                    Text("Yes")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(value == true ? Color.green : Color.planCardBackground)
                .foregroundColor(value == true ? .white : .planTextPrimary)
                .cornerRadius(28)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                onSelect(false)
            }) {
                HStack {
                    Image(systemName: "xmark")
                        .font(.headline)
                    Text("No")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(value == false ? Color.red : Color.planCardBackground)
                .foregroundColor(value == false ? .white : .planTextPrimary)
                .cornerRadius(28)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Time Input View

struct TimeInputView: View {
    @State var hours: Int = 0
    @State var minutes: Int = 0
    let value: String
    let onValueChange: (String) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            VStack {
                Stepper("", value: $hours, in: 0...23)
                Text("\(hours)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.planAccent)
                Text("Hours")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
            }
            
            Text(":")
                .font(.title)
                .fontWeight(.bold)
            
            VStack {
                Stepper("", value: $minutes, in: 0...59)
                Text("\(minutes)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.planAccent)
                Text("Minutes")
                    .font(.caption)
                    .foregroundColor(.planTextSecondary)
            }
        }
        .padding()
        .background(Color.planCardBackground)
        .cornerRadius(12)
        .onChange(of: hours) { updateTime() }
        .onChange(of: minutes) { updateTime() }
        .onAppear {
            parseTime()
        }
    }
    
    private func parseTime() {
        let components = value.split(separator: ":")
        if components.count == 2,
           let h = Int(components[0]),
           let m = Int(components[1]) {
            hours = h
            minutes = m
        }
    }
    
    private func updateTime() {
        let timeString = String(format: "%02d:%02d", hours, minutes)
        onValueChange(timeString)
    }
}

// MARK: - Text Input View

struct TextInputView: View {
    @State var text: String
    let placeholder: String
    let onTextChange: (String) -> Void
    
    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
            .foregroundColor(.planTextPrimary)
            .padding()
            .background(Color.planCardBackground)
            .cornerRadius(12)
            .onChange(of: text) {
                onTextChange(text)
            }
    }
}

