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
                    .font(.title2)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(title)
                    .font(.caption)
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
                    .font(.title2)
                    .foregroundColor(status.color)
            }
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(status.text)
                    .font(.caption)
                    .fontWeight(.semibold)
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
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(feedback.type.color)
                Text(feedback.message)
                    .font(.caption)
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
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .foregroundColor(isCompleted ? .white : .gray)
            Spacer()
        }
    }
} 