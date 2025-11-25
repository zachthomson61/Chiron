import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.neueMontrealBold(size: 22))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(.white)
                Text(title)
                    .font(.neueMontrealRegular(size: 12))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

struct FormStatusIndicator: View {
    let title: String
    let status: FormStatus
    let icon: String
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.2))
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.neueMontrealBold(size: 22))
                    .foregroundColor(status.color)
            }
            VStack(spacing: 2) {
                Text(title)
                    .font(.neueMontrealRegular(size: 12))
                    .foregroundColor(.gray)
                Text(status.text)
                    .font(.neueMontrealSemiBold(size: 12))
                    .foregroundColor(status.color)
            }
        }
    }
}

struct FeedbackCardView: View {
    let feedback: FeedbackItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feedback.type.icon)
                .foregroundColor(feedback.type.color)
                .font(.neueMontrealBold(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.neueMontrealSemiBold(size: 15))
                    .foregroundColor(feedback.type.color)
                Text(feedback.message)
                    .font(.neueMontrealRegular(size: 12))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

struct ChecklistItem: View {
    let text: String
    let isCompleted: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .gray)
                .font(.neueMontrealBold(size: 20))
            Text(text)
                .font(.neueMontrealRegular(size: 15))
                .foregroundColor(isCompleted ? .white : .gray)
            Spacer()
        }
    }
} 