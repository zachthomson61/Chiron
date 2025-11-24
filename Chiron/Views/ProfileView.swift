import SwiftUI
import PhotosUI

// MARK: - Profile View Constants

struct ProfileViewConstants {
    static let coverImageHeight: CGFloat = 200
    static let avatarSize: CGFloat = 100
    static let cardCornerRadius: CGFloat = 16
    static let badgeSize: CGFloat = 80
    static let sectionSpacing: CGFloat = 24
    static let horizontalPadding: CGFloat = 20
}

// MARK: - Main Profile View

struct ProfileView: View {
    @State private var userProfile = UserProfile.mock()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSettings = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cover image + Avatar + Name - no horizontal padding to extend to edges
                ProfileHeaderView(
                    profileImage: userProfile.profileImage,
                    name: userProfile.name,
                    gender: userProfile.gender,
                    selectedPhotoItem: $selectedPhotoItem
                )
                
                // Content sections with horizontal padding
                VStack(spacing: ProfileViewConstants.sectionSpacing) {
                    // Stats Row
                    ProfileStatsRow(
                        memberSince: userProfile.formattedMemberSince,
                        workouts: userProfile.totalWorkouts,
                        lbsLifted: userProfile.formattedLbsLifted
                    )
                    
                    // Achievements Section
                    AchievementsSection(achievements: userProfile.achievements)
                }
                .padding(.horizontal, ProfileViewConstants.horizontalPadding)
            }
        }
        .background(Color.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.textPrimary)
                }
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let newValue = newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    userProfile.profileImage = image
                    // TODO: Persist profile image to UserProfile storage
                }
            }
        }
    }
}

// MARK: - Profile Header View

struct ProfileHeaderView: View {
    let profileImage: UIImage?
    let name: String
    let gender: String?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    
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
                    // Avatar
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
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
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Name
                    Text(name)
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .foregroundColor(.textPrimary)
                        .padding(.bottom, 8)
                }
                .padding(.leading, ProfileViewConstants.horizontalPadding)
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
                // Male cover image - extends to all screen edges
                Image("MaleCover")
                    .resizable()
                    .scaledToFill()
                    .frame(height: ProfileViewConstants.coverImageHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(statusBarOverlay)
                    .ignoresSafeArea(edges: [.top, .horizontal])
            } else {
                // Default geometric pattern for non-male genders
                geometricPatternBackground
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Dark overlay that extends the image's top color into the status bar/Dynamic Island area.
    /// Color matches the dark top pixels of the MaleCover image.
    private var statusBarOverlay: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Color(red: 0.05, green: 0.05, blue: 0.06)
                    .frame(height: geometry.safeAreaInsets.top)
            }
            Spacer()
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
            // Member Since
            VStack(alignment: .leading, spacing: 4) {
                Text("Member Since")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(memberSince)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Workouts
            VStack(alignment: .leading, spacing: 4) {
                Text("Workouts")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("\(workouts)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Lbs Lifted
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

// MARK: - Promo Card View

struct PromoCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite friends to Chiron and get a free month.")
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            
            Button(action: {
                // TODO: Implement referral/invite functionality
            }) {
                Text("Send Invite")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryPurple)
            }
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
            // Header
            HStack {
                Text("Achievements")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Button(action: {
                    // TODO: Navigate to full achievements view
                    showAllAchievements = true
                }) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundColor(.primaryPurple)
                }
            }
            
            // Badges
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
            // Badge background (circular)
            Circle()
                .fill(achievement.badgeColor)
                .frame(width: ProfileViewConstants.badgeSize, height: ProfileViewConstants.badgeSize)
            
            // Subtle pattern overlay
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
            
            // Center content (black rounded rectangle)
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

// MARK: - Coach Card View

struct CoachCardView: View {
    let coach: Coach
    @State private var showChangeCoach = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Your Coach")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Button(action: {
                    // TODO: Implement coach change functionality
                    showChangeCoach = true
                }) {
                    Text("Change")
                        .font(.subheadline)
                        .foregroundColor(.primaryPurple)
                }
            }
            
            // Coach Card
            HStack(spacing: 16) {
                // Coach Avatar
                Group {
                    if let avatarImage = coach.avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundColor(.textSecondary)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                
                // Coach Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(coach.name)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    
                    Text(coach.description)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: ProfileViewConstants.cardCornerRadius)
                    .fill(Color(white: 0.15))
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

