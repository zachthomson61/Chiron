import SwiftUI
import AVKit
import AVFoundation

struct BodyweightSquatOverview: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCameraSetup = false
    @State private var showAlternativeSetup = false
    @State private var selectedTab = 0
    @State private var showActiveWorkout = false
    
    // Callback to navigate back to exercise selection
    var onFinishExercise: (() -> Void)?
    
    // Initialize with optional callback
    init(viewModel: WorkoutViewModel, onFinishExercise: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onFinishExercise = onFinishExercise
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        // Collapsing header that shrinks and fades as you scroll
                        let maxHeaderHeight = UIScreen.main.bounds.height * 0.7
                        GeometryReader { geo in
                            let offset = geo.frame(in: .named("scroll")).minY
                            let currentHeight = max(maxHeaderHeight - offset, 0)
                            let opacity = max(0, min(1, currentHeight / maxHeaderHeight))
                            
                            ZStack(alignment: .bottom) {
                                CroppedDemoVideoHeader(videoName: "bodyweight_squat_demo")
                                
                                // Gradient overlay for readability
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.0),
                                        Color.black.opacity(0.15),
                                        Color.black.opacity(0.35),
                                        Color.black.opacity(0.55)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: currentHeight)
                            .clipped()
                            .opacity(opacity)
                            .offset(y: offset < 0 ? -offset : 0)
                            .ignoresSafeArea(.container, edges: .top)
                        }
                        .frame(height: maxHeaderHeight)

                        // Scrollable menu content
                        VStack(alignment: .leading, spacing: 16) {
                            // Tab selector inside scroll
                            TabSelector(selectedTab: $selectedTab)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            
                            Text("Bodyweight Squat")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            
                            switch selectedTab {
                            case 0:
                                FlowContent()
                            case 1:
                                DosContent()
                            case 2:
                                DontsContent()
                            default:
                                FlowContent()
                            }
                            
                            Button(action: {
                                showCameraSetup = true
                                viewModel.startWorkout()
                            }) {
                                Text("Continue to Camera Setup")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(Color.primaryPurple)
                                    .cornerRadius(24)
                            }
                            .padding(.top, 16)
                        }
                        .padding(20)
                    }
                }
                .coordinateSpace(name: "scroll")

                // Floating back button in the top-left corner
                GeometryReader { geo in
                    VStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, geo.safeAreaInsets.top + 60) // Move below Dynamic Island
                        Spacer()
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCameraSetup) {
            BodyweightSquatCameraSetupView(viewModel: viewModel)
        }
        // Removed second cover to avoid bouncing between covers
    }
    
}

struct TabSelector: View {
    @Binding var selectedTab: Int
    private let tabs = ["Setup", "Dos", "Don'ts"]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 8) {
                            Text(tabs[index])
                            .font(.subheadline)
                            .fontWeight(selectedTab == index ? .semibold : .medium)
                .foregroundColor(selectedTab == index ? .primaryPurple : .white.opacity(0.75))
                        
                        Rectangle()
                            .fill(selectedTab == index ? Color.primaryPurple : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGray6).opacity(0.25))
        .cornerRadius(8)
    }
}

struct FlowContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master the basics: smooth depth, neutral spine, knees over toes.")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Stand tall, feet hip‑to‑shoulder width, toes slightly out.")
                StepRow(number: 2, text: "Sit back and down until thighs are near parallel.")
                StepRow(number: 3, text: "Keep chest up, spine neutral, knees tracking over toes.")
                StepRow(number: 4, text: "Drive through heels to stand; squeeze glutes at the top.")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct DosContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key things to focus on during your squat:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: true, text: "Keep your chest up and spine neutral")
                DoDontRow(isDo: true, text: "Push your knees out in line with your toes")
                DoDontRow(isDo: true, text: "Sit back as if sitting into a chair")
                DoDontRow(isDo: true, text: "Keep your weight in your heels")
                DoDontRow(isDo: true, text: "Breathe steadily throughout the movement")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct DontsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common mistakes to avoid:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: false, text: "Letting your knees cave inward")
                DoDontRow(isDo: false, text: "Rounding your lower back")
                DoDontRow(isDo: false, text: "Lifting your heels off the ground")
                DoDontRow(isDo: false, text: "Going too fast or bouncing at the bottom")
                DoDontRow(isDo: false, text: "Not going deep enough (thighs should be near parallel)")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct DoDontRow: View {
    let isDo: Bool
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDo ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isDo ? .green : .red)
                .font(.title3)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Step \(number)")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primaryPurple)
                .frame(width: 72, alignment: .leading)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// Cropped demo header that focuses on the outlined portion (left side with the woman demonstrating)
struct CroppedDemoVideoHeader: View {
    let url: URL?
    
    init(videoName: String, ext: String = "mp4") {
        self.url = Bundle.main.url(forResource: videoName, withExtension: ext)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            if let url = url {
                LoopingVideoView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        TopEdgeProjection(url: url)
                            .allowsHitTesting(false),
                        alignment: .top
                    )
            } else {
                Image("SquatSetupDiagram")
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

// Projects the top 1-2px of the video into the top safe-area and blurs it,
// mimicking the Yoga AI UI effect under the Dynamic Island
struct TopEdgeProjection: View {
    let url: URL
    private let sliceHeight: CGFloat = 2
    
    var body: some View {
        GeometryReader { geo in
            LoopingVideoView(url: url)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle().frame(height: sliceHeight)
                        Spacer(minLength: 0)
                    }
                )
                .scaleEffect(x: 1, y: max((geo.safeAreaInsets.top) / max(sliceHeight, 1), 1), anchor: .top)
                .blur(radius: 16)
                .ignoresSafeArea(.container, edges: .top)
        }
        .frame(height: 0) // overlay only
    }
}

// A control-less looping video using AVQueuePlayer + AVPlayerLooper so no play button appears
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    
    class Coordinator {
        let player: AVQueuePlayer = AVQueuePlayer()
        var looper: AVPlayerLooper?
        
        func configure(with url: URL) {
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.configure(with: url)
        return coordinator
    }
    
    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = context.coordinator.player
        view.playerLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            context.coordinator.player.isMuted = true
            context.coordinator.player.play()
        }
        return view
    }
    
    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        // If the url ever changes in future, reconfigure the looper
        // (not needed now since url is constant)
    }
    
    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.player.pause()
    }
    
    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
