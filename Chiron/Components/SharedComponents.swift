import SwiftUI

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.neueMontrealRegular(size: 15))
                .foregroundColor(.primaryPurple)
                .frame(width: 20)
            Text(text)
                .font(.neueMontrealRegular(size: 15))
                .foregroundColor(.textPrimary)
            Spacer()
        }
    }
}

struct FormIndicator: View {
    let title: String
    let status: FormStatus
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.neueMontrealRegular(size: 15))
                .foregroundColor(status.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.neueMontrealRegular(size: 11))
                    .foregroundColor(.textSecondary)
                Text(status.text)
                    .font(.neueMontrealSemiBold(size: 12))
                    .foregroundColor(status.color)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
        .frame(width: 100)
    }
} 