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
    @ObservedObject private var badges = BadgeCenter.shared
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

                    BadgeAchievementsSection(earnedBadges: badges.earnedBadges)
                }
                .padding(.horizontal, ProfileViewConstants.horizontalPadding)
                .padding(.bottom, 32)
            }
        }
        .dottedTabBackground(corners: [.bottomTrailing])
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
                // Re-evaluate consistency / mastery / volume badges against
                // the freshly loaded history so the gallery picks up anything
                // that crossed a threshold while the user was outside the app
                // (or before the badge system was installed).
                BadgeCenter.shared.recomputeFromHistory(setLogs: logs)
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
                colors: [Color.surfaceElevated, Color.surface],
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
                .fill(Color.surface)
        )
    }
}

// MARK: - Badge Achievements Section

/// Profile-page surface for the new badge system. Shows the earned badges in
/// a horizontal scroller and offers a "View All" link into a full gallery
/// (locked + unlocked, grouped by category). When the user has no badges yet,
/// surfaces a hint that points them at the Track tab so the empty state never
/// reads as "broken".
struct BadgeAchievementsSection: View {
    let earnedBadges: [Badge]
    @State private var showGallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Achievements")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                if !earnedBadges.isEmpty {
                    Text("\(earnedBadges.count) of \(BadgeCatalog.all.count)")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Button {
                    showGallery = true
                } label: {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundColor(.primaryPurple)
                }
            }

            if earnedBadges.isEmpty {
                BadgeEmptyHintView { showGallery = true }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(earnedBadges) { badge in
                            BadgeTile(badge: badge, isLocked: false)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showGallery) {
            BadgeGallerySheet(isPresented: $showGallery)
        }
    }
}

// MARK: - Badge Tile

/// Vertical stack of artwork + title. Used in both the profile scroller and
/// the full gallery; locked tiles render the same layout with desaturated art
/// so the user can see what's coming next.
struct BadgeTile: View {
    let badge: Badge
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            BadgeArtworkView(badge: badge, size: 78, isLocked: isLocked)
            Text(badge.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isLocked ? .textSecondary : .textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 96)
        }
    }
}

// MARK: - Empty Hint

private struct BadgeEmptyHintView: View {
    let onTapViewAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rosette")
                .font(.title2)
                .foregroundStyle(Color.primaryPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text("No achievements yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Text("Complete a set in the Track tab to earn your first badge.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Browse", action: onTapViewAll)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.primaryPurple)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ProfileViewConstants.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}

// MARK: - Badge Gallery Sheet

/// Full-screen catalogue grouped by category. Earned badges render in color;
/// locked badges render desaturated alongside their tagline so the user can
/// read the unlock criteria without having to remember each rule.
struct BadgeGallerySheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var center = BadgeCenter.shared

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    earnedSummary
                    ForEach(BadgeCategory.allCases) { category in
                        categorySection(for: category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.textPrimary)
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var earnedSummary: some View {
        let earned = center.earnedBadgeIDs.count
        let total = BadgeCatalog.all.count
        let progress = total == 0 ? 0 : Double(earned) / Double(total)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(earned) of \(total) earned")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.primaryPurple)
            }
            ProgressView(value: progress)
                .tint(.primaryPurple)
        }
    }

    @ViewBuilder
    private func categorySection(for category: BadgeCategory) -> some View {
        let badges = BadgeCatalog.all.filter { $0.category == category }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(category.gradient)
                    .frame(width: 10, height: 10)
                Text(category.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(progressLabel(for: badges))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(badges) { badge in
                    BadgeGalleryCell(badge: badge, isEarned: center.isEarned(badge))
                }
            }
        }
    }

    private func progressLabel(for badges: [Badge]) -> String {
        let earned = badges.filter { center.isEarned($0) }.count
        return "\(earned)/\(badges.count)"
    }
}

private struct BadgeGalleryCell: View {
    let badge: Badge
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 8) {
            BadgeArtworkView(badge: badge, size: 78, isLocked: !isEarned)
            Text(badge.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isEarned ? .textPrimary : .textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(badge.tagline)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfileView()
    }
    .preferredColorScheme(.dark)
}
