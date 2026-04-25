import SwiftUI
import PhotosUI

// MARK: - Profile View Constants

struct ProfileViewConstants {
    /// Tall enough that, even with the cover bleeding up under the dynamic
    /// island, the figure inside the photo lands well below the island.
    static let coverImageHeight: CGFloat = 280
    static let avatarSize: CGFloat = 100
    static let cardCornerRadius: CGFloat = 16
    static let badgeSize: CGFloat = 80
    static let sectionSpacing: CGFloat = 24
    static let horizontalPadding: CGFloat = 20
}

// MARK: - Main Profile View

struct ProfileView: View {
    @StateObject private var account = AccountStore.shared
    @State private var onboardingProfile: ChironUserProfile?
    @State private var totalWorkouts: Int = 0
    @State private var totalLbsLifted: Int = 0

    @State private var showSettings = false
    @State private var showCompleteProfile = false
    @State private var showAvatarChooser = false
    @State private var showCameraPicker = false
    @State private var showLibraryPicker = false

    private let profileStore = UserDefaultsUserProfileStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeaderView(
                    profileImage: account.profileImage,
                    name: displayName,
                    gender: onboardingProfile?.gender.rawValue,
                    onAvatarTap: { showAvatarChooser = true }
                )

                VStack(spacing: ProfileViewConstants.sectionSpacing) {
                    ProfileStatsRow(
                        memberSince: formattedMemberSince,
                        workouts: totalWorkouts,
                        lbsLifted: formattedLbsLifted
                    )

                    if account.details == nil {
                        CompleteProfileCard {
                            showCompleteProfile = true
                        }
                    }

                    if onboardingProfile != nil {
                        TrainingProfileCard(profile: trainingProfileBinding)
                    }

                    AchievementsSection(achievements: achievements)
                }
                .padding(.horizontal, ProfileViewConstants.horizontalPadding)
                .padding(.bottom, 32)
            }
        }
        .background(Color.background)
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                }
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showCompleteProfile) {
            let storedName = account.details?.name ?? ""
            let nameParts = storedName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            CompleteProfileSheet(
                mode: account.details == nil ? .create : .edit,
                initialFirstName: nameParts.first ?? "",
                initialLastName: nameParts.count > 1 ? nameParts[1] : "",
                initialEmail: account.details?.email ?? ""
            ) { name, email, password in
                account.save(name: name, email: email, password: password)
            }
        }
        .confirmationDialog("Profile Photo", isPresented: $showAvatarChooser, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCameraPicker = true }
            }
            Button("Choose from Library") { showLibraryPicker = true }
            if account.profileImage != nil {
                Button("Remove Photo", role: .destructive) {
                    account.updateProfileImage(nil)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraImagePicker { image in
                account.updateProfileImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibraryPicker) {
            PhotoLibraryPicker { image in
                account.updateProfileImage(image)
            }
        }
        .onAppear {
            onboardingProfile = profileStore.load()
            fetchStats()
        }
    }

    // MARK: - Derived display values

    private var displayName: String {
        if let stored = account.details?.name, !stored.isEmpty {
            return stored
        }
        return "Welcome to Chiron"
    }

    private var memberSinceDate: Date {
        account.details?.createdAt ?? onboardingProfile?.createdAt ?? Date()
    }

    private var formattedMemberSince: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: memberSinceDate)
    }

    private var formattedLbsLifted: String {
        if totalLbsLifted >= 1000 {
            let thousands = Double(totalLbsLifted) / 1000.0
            if thousands >= 100 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands).replacingOccurrences(of: ".0", with: "")
            }
        }
        return "\(totalLbsLifted)"
    }

    /// Mock achievements until the achievement system is built. Pulled out of
    /// `UserProfile.mock()` so the profile view doesn't depend on the legacy
    /// display-layer struct.
    private var achievements: [Achievement] {
        [
            Achievement(value: "500", label: "CALORIES", badgeColor: Color(red: 1.0, green: 0.8, blue: 0.9)),
            Achievement(value: "1000", label: "CALORIES", badgeColor: Color(red: 1.0, green: 0.8, blue: 0.9))
        ]
    }

    // MARK: - Editable training profile

    /// Bridges `TrainingProfileCard`'s binding back to the persistent store
    /// and notifies the coaching manager so the next set picks up the new
    /// values. Only built when `onboardingProfile` is non-nil — the call site
    /// already gates on that, so the force-unwrap in `get` is safe.
    private var trainingProfileBinding: Binding<ChironUserProfile> {
        Binding(
            get: { onboardingProfile! },
            set: { newValue in
                onboardingProfile = newValue
                try? profileStore.save(newValue)
                OpenAICoachingManager.shared.refreshProfile()
            }
        )
    }

    // MARK: - Stats

    private func fetchStats() {
        let userId = UserManager.shared.getUserId()
        WorkoutLogService.shared.getAllHistoryForUser(userId: userId) { result in
            guard case let .success(logs) = result else { return }
            let workouts = Set(logs.map { $0.workoutLogId }).count
            let lbs = logs.reduce(into: 0.0) { running, log in
                if let weight = log.weight, let reps = log.reps {
                    running += weight * Double(reps)
                }
            }
            DispatchQueue.main.async {
                self.totalWorkouts = workouts
                self.totalLbsLifted = Int(lbs)
            }
        }
    }
}

// MARK: - Profile Header View

struct ProfileHeaderView: View {
    let profileImage: UIImage?
    let name: String
    let gender: String?
    let onAvatarTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            CoverImageView(gender: gender)
                .frame(height: ProfileViewConstants.coverImageHeight)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: [.top, .horizontal])

            // Content overlay
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                    .frame(height: ProfileViewConstants.coverImageHeight - ProfileViewConstants.avatarSize / 2)

                HStack(alignment: .bottom, spacing: 16) {
                    Button(action: onAvatarTap) {
                        Group {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .frame(width: ProfileViewConstants.avatarSize, height: ProfileViewConstants.avatarSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.background, lineWidth: 4)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white, Color.primaryPurple)
                                .background(Circle().fill(Color.background))
                                .offset(x: 4, y: 4)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Text(name)
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .foregroundColor(.textPrimary)
                        .padding(.bottom, 8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.leading, ProfileViewConstants.horizontalPadding)
                .padding(.trailing, ProfileViewConstants.horizontalPadding)
            }
        }
    }
}

// MARK: - Cover Image View

/// Displays the profile cover image based on user's gender preference.
/// Shows MaleCover image for "male" or when no gender is selected (default).
/// Falls back to geometric pattern for other gender values.
struct CoverImageView: View {
    let gender: String?

    var body: some View {
        ZStack {
            if gender == "male" || gender == nil {
                Image("MaleCover")
                    .resizable()
                    .scaledToFill()
                    .frame(height: ProfileViewConstants.coverImageHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .ignoresSafeArea(edges: [.top, .horizontal])
            } else {
                geometricPatternBackground
            }
        }
    }

    /// Default geometric pattern background with interlocking block design.
    private var geometricPatternBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.18),
                    Color(red: 0.12, green: 0.12, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { geometry in
                let spacing: CGFloat = 40
                let blockSize: CGFloat = 12

                ZStack {
                    ForEach(0..<Int(geometry.size.height / spacing) + 2, id: \.self) { row in
                        ForEach(0..<Int(geometry.size.width / spacing) + 2, id: \.self) { col in
                            let x = CGFloat(col) * spacing
                            let y = CGFloat(row) * spacing
                            let offset = (row % 2 == 0) ? spacing / 2 : 0

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: blockSize, height: blockSize)
                                .offset(x: x + offset - spacing, y: y - spacing)

                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.03))
                                .frame(width: blockSize * 0.6, height: blockSize * 0.6)
                                .offset(x: x + offset - spacing + blockSize * 0.2, y: y - spacing + blockSize * 0.2)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Profile Stats Row

struct ProfileStatsRow: View {
    let memberSince: String
    let workouts: Int
    let lbsLifted: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Member Since")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(memberSince)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Workouts")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("\(workouts)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Lbs Lifted")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(lbsLifted)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Complete Profile CTA Card

/// Anonymous-state prompt that opens the `CompleteProfileSheet`. Hidden once
/// the user has saved an `AccountDetails` record.
struct CompleteProfileCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish setting up your profile")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("Add your name, email, and a password to personalize your account. Your training profile is already saved.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            Button(action: action) {
                Text("Complete User Profile")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primaryPurple)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: ProfileViewConstants.cardCornerRadius)
                .fill(Color(white: 0.15))
        )
    }
}

// MARK: - Achievements Section

struct AchievementsSection: View {
    let achievements: [Achievement]
    @State private var showAllAchievements = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Achievements")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button(action: {
                    showAllAchievements = true
                }) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundColor(.primaryPurple)
                }
            }

            if achievements.isEmpty {
                Text("No achievements yet")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(achievements) { achievement in
                            AchievementBadgeView(achievement: achievement)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

// MARK: - Achievement Badge View

struct AchievementBadgeView: View {
    let achievement: Achievement

    var body: some View {
        ZStack {
            Circle()
                .fill(achievement.badgeColor)
                .frame(width: ProfileViewConstants.badgeSize, height: ProfileViewConstants.badgeSize)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: ProfileViewConstants.badgeSize / 2
                    )
                )

            VStack(spacing: 2) {
                Text(achievement.value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(achievement.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.7))
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfileView()
    }
    .preferredColorScheme(.dark)
}
