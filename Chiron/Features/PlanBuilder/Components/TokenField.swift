import SwiftUI

// MARK: - Token Field Component

struct TokenField: View {
    let tokens: [InjuryNote]
    let onRemove: (InjuryNote) -> Void
    
    var body: some View {
        if tokens.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(tokens) { token in
                    TokenChip(
                        text: token.raw,
                        onRemove: { onRemove(token) }
                    )
                }
            }
        }
    }
}

// MARK: - Token Chip Component

struct TokenChip: View {
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.planTextPrimary)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.planTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.planCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.planAccent, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TokenField(
            tokens: [
                InjuryNote(raw: "shoulder impingement"),
                InjuryNote(raw: "low back tightness"),
                InjuryNote(raw: "sore knee")
            ],
            onRemove: { _ in }
        )
        .padding()
    }
    .background(Color.planBackground)
    .preferredColorScheme(.dark)
}
