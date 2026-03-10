import SwiftUI
#if os(iOS)
import UIKit

// MARK: - Plan Builder Theme

extension Color {
    // Use existing app color palette
    static let planAccent = Color.primaryPurple
    static let planAccentDark = Color.secondaryPurple
    
    // Background colors (matching app theme)
    static let planBackground = Color.background
    static let planCardBackground = Color.white.opacity(0.08)
    static let planCardBackgroundSelected = Color.primaryPurple.opacity(0.2)
    
    // Text colors (matching app theme)
    static let planTextPrimary = Color.textPrimary
    static let planTextSecondary = Color.textSecondary
}

// MARK: - Component Styles

struct PlanChipStyle: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .font(.neueMontrealSemiBold(size: 15))
            .foregroundColor(isSelected ? .textPrimary : .planTextPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.planAccent : Color.planCardBackground)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.clear : Color.planAccent.opacity(0.3), lineWidth: 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct PlanButtonStyle: ButtonStyle {
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.neueMontrealSemiBold(size: 17))
            .foregroundColor(isPrimary ? .textPrimary : .planTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isPrimary ? Color.planAccent : Color.planCardBackground)
            .cornerRadius(28)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PlanCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.planCardBackground)
            .cornerRadius(16)
    }
}

struct PlanSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
    }
}

// MARK: - View Extensions

extension View {
    func planChipStyle(isSelected: Bool) -> some View {
        modifier(PlanChipStyle(isSelected: isSelected))
    }
    
    func planCardStyle() -> some View {
        modifier(PlanCardStyle())
    }
    
    func planSectionStyle() -> some View {
        modifier(PlanSectionStyle())
    }
}

// MARK: - Reusable Components

struct PlanSectionHeader: View {
    let title: String
    let subtitle: String?
    
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.neueMontrealBold(size: 17))
                .foregroundColor(.planTextPrimary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.neueMontrealRegular(size: 12))
                    .foregroundColor(.planTextSecondary)
            }
        }
    }
}

struct PlanChipGrid<T: Hashable>: View {
    let items: [T]
    let selected: Set<T>
    let label: (T) -> String
    let icon: ((T) -> String)?
    let onToggle: (T) -> Void
    
    init(items: [T], 
         selected: Set<T>, 
         label: @escaping (T) -> String,
         icon: ((T) -> String)? = nil,
         onToggle: @escaping (T) -> Void) {
        self.items = items
        self.selected = selected
        self.label = label
        self.icon = icon
        self.onToggle = onToggle
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
            ForEach(items, id: \.self) { item in
                Button(action: { onToggle(item) }) {
                    HStack(spacing: 6) {
                        if let icon = icon {
                            Image(systemName: icon(item))
                                .font(.neueMontrealRegular(size: 12))
                        }
                        Text(label(item))
                    }
                }
                .planChipStyle(isSelected: selected.contains(item))
            }
        }
    }
}

struct MuscleGroupGrid: View {
    let muscles: [MuscleGroup]
    let selected: Set<MuscleGroup>
    let onToggle: (MuscleGroup) -> Void
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
            ForEach(muscles, id: \.self) { muscle in
                MuscleGroupCard(
                    muscle: muscle,
                    isSelected: selected.contains(muscle),
                    onToggle: { onToggle(muscle) }
                )
            }
        }
    }
}

struct MuscleGroupCard: View {
    let muscle: MuscleGroup
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                // Anatomical muscle icon - now fills the entire card
                ZStack {
                    // Anatomical representation fills the entire card
                    AnatomicalMuscleView(muscle: muscle)
                    
                    // Selection border overlay
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.primaryPurple : Color.clear, lineWidth: 3)
                }
                .frame(width: 80, height: 80)
                
                // Muscle name
                Text(muscle.displayName)
                    .font(.neueMontrealSemiBold(size: 12))
                    .foregroundColor(.planTextPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AnatomicalMuscleView: View {
    let muscle: MuscleGroup
    
    var body: some View {
        // Robust load to support loose PNGs in the bundle (not just asset catalog)
        loadedImage(for: muscle.imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 80, height: 80)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func loadedImage(for name: String) -> Image {
        #if os(iOS)
        // Try standard UIImage(named:) which searches asset catalogs and bundle images
        if let ui = UIImage(named: name) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Try explicit .png in main bundle
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Defensive: also try underscore variant (e.g., "Lower_Back_Icon")
        let underscored = name.replacingOccurrences(of: " ", with: "_")
        if let ui = UIImage(named: underscored) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        if let url = Bundle.main.url(forResource: underscored, withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui).renderingMode(.original)
        }
        // Fallback placeholder so UI remains stable
        return Image(systemName: "photo")
        #else
        return Image(name)
        #endif
    }
}

struct PlanSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.neueMontrealRegular(size: 15))
                    .foregroundColor(.planTextPrimary)
                Spacer()
                Text(String(format: format, Int(value)))
                    .font(.neueMontrealBold(size: 17))
                    .foregroundColor(.planAccent)
            }
            
            Slider(value: $value, in: range, step: step)
                .accentColor(.planAccent)
        }
    }
}

struct PlanToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.neueMontrealRegular(size: 15))
                    .foregroundColor(.planTextPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.neueMontrealRegular(size: 12))
                        .foregroundColor(.planTextSecondary)
                }
            }
        }
        .tint(.planAccent)
    }
}
#endif
