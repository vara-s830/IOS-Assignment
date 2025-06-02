class PlaybackManager {
    static let shared = PlaybackManager()
    
    // MARK: – Published Playback State
    @Published private(set) var playerState: PlayerState = .stopped
    @Published private(set) var currentSong: Song? = nil
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var playlist: [Song] = []
    
    private var timeObserver: AnyCancellable?
    private var interruptionObserver: AnyCancellable?
    private var routeChangeObserver: AnyCancellable?
    
    private init() {
        configureAudioSessionNotifications()
        configurePlaybackTimeObserver()
    }
    
    // … methods to play, pause, skip, etc.
}
private func configureAudioSessionNotifications() {
    let center = NotificationCenter.default
    interruptionObserver = center
        .publisher(for: AVAudioSession.interruptionNotification)
        .sink { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }
            
            switch type {
            case .began:
                // Audio interruption began—pause playback and update state
                self?.handleInterruptionBegan()
            case .ended:
                // Audio interruption ended—optionally resume
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self?.resumeAfterInterruption()
                    }
                }
            @unknown default:
                break
            }
        }
    
    // **Route Change Notifications** (e.g., headphones unplugged)
    routeChangeObserver = center
        .publisher(for: AVAudioSession.routeChangeNotification)
        .sink { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
            else { return }
            
            if reason == .oldDeviceUnavailable {
                // Headphones unplugged—pause playback and update state
                self?.handleHeadphonesUnplugged()
            }
        }
}

private func handleInterruptionBegan() {
    // Only change state if currently playing
    if playerState == .playing {
        pausePlayback()         // your internal pause routine
        playerState = .paused   // notify UI
    }
}

private func resumeAfterInterruption() {
    // Decide if you want to auto-resume on interruption end
    playCurrentSong()          // your internal play routine
}

private func handleHeadphonesUnplugged() {
    // Pause if playing via headphones—don’t continue blasting through speaker
    if playerState == .playing {
        pausePlayback()
        playerState = .paused
    }
}
private func configurePlaybackTimeObserver() {
    // Assuming you use AVPlayer for playback:
    timeObserver = Timer
        .publish(every: 0.5, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            guard let self = self, let player = self.avPlayer else { return }
            self.currentTime = player.currentTime().seconds
        }
}
class PlaylistViewModel: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published var selectedIndex: Int? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        PlaybackManager.shared.$playlist
            .receive(on: DispatchQueue.main)
            .assign(to: \.songs, on: self)
            .store(in: &cancellables)
        
        // If user taps a row, you’ll set selectedIndex.
        // In didSet of selectedIndex, call PlaybackManager.shared.play(at: selectedIndex!)
    }
}
class NowPlayingViewModel: ObservableObject {
    @Published private(set) var title: String = ""
    @Published private(set) var artist: String = ""
    @Published private(set) var progress: Double = 0    // 0.0 – 1.0
    @Published private(set) var isPlaying: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let manager = PlaybackManager.shared
        
        // Subscribe to currentSong
        manager.$currentSong
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] song in
                self?.title = song.title
                self?.artist = song.artist
            }
            .store(in: &cancellables)
        
        // Subscribe to currentTime & duration to compute progress
        Publishers.CombineLatest(manager.$currentTime, manager.$currentSong)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (time, song) in
                guard let duration = song?.duration, duration > 0 else {
                    self?.progress = 0
                    return
                }
                self?.progress = time / duration
            }
            .store(in: &cancellables)
        
        // Subscribe to playerState
        manager.$playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isPlaying = (state == .playing)
            }
            .store(in: &cancellables)
    }
    
    // Expose play/pause actions to UI
    func togglePlayPause() {
        let manager = PlaybackManager.shared
        if isPlaying {
            manager.pausePlayback()
        } else {
            manager.resumePlayback()
        }
    }
}
struct PlaylistView: View {
    @StateObject private var viewModel = PlaylistViewModel()
    
    var body: some View {
        List(viewModel.songs.indices, id: \.self) { index in
            let song = viewModel.songs[index]
            HStack {
                VStack(alignment: .leading) {
                    Text(song.title).font(.headline)
                    Text(song.artist).font(.subheadline)
                }
                Spacer()
                if viewModel.selectedIndex == index {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectedIndex = index
                PlaybackManager.shared.play(at: index)
            }
        }
    }
}

struct NowPlayingView: View {
    @StateObject private var viewModel = NowPlayingViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            Text(viewModel.title).font(.title2).bold()
            Text(viewModel.artist).font(.subheadline).foregroundColor(.gray)
            
            // Progress Bar
            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal)
            
            // Play/Pause Button
            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
            }
        }
        .padding()
    }
}
class NowPlayingViewController: UIViewController {
    private let viewModel = NowPlayingViewModel()
    private var cancellables = Set<AnyCancellable>()
    
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let playPauseButton = UIButton(type: .system)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        bindViewModel()
    }
    
    private func setupLayout() {
        // Add titleLabel, artistLabel, progressView, playPauseButton to view
        // Set Auto Layout constraints accordingly
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
    }
    
    private func bindViewModel() {
        viewModel.$title
            .receive(on: RunLoop.main)
            .assign(to: \.text, on: titleLabel)
            .store(in: &cancellables)
        
        viewModel.$artist
            .receive(on: RunLoop.main)
            .assign(to: \.text, on: artistLabel)
            .store(in: &cancellables)
        
        viewModel.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] prog in
                self?.progressView.progress = Float(prog)
            }
            .store(in: &cancellables)
        
        viewModel.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                let imageName = playing ? "pause.circle.fill" : "play.circle.fill"
                self?.playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
            }
            .store(in: &cancellables)
    }
    
    @objc private func playPauseTapped() {
        viewModel.togglePlayPause()
    }
}
import AVFoundation
import Combine
import UIKit

var cancellable: AnyCancellable?
cancellable = NotificationCenter.default
    .publisher(for: AVAudioSession.interruptionNotification)
    .sink { notification in
        print("Interruption fired: \(notification.userInfo ?? [:])")
    }

// Manually post a fake interruption to test:
NotificationCenter.default.post(
    name: AVAudioSession.interruptionNotification,
    object: nil,
    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
)
func testInterruptionPausesPlayback() {
    let manager = PlaybackManager.shared
    let expectation = XCTestExpectation(description: "Player pauses on interruption")
    let cancellable = manager.$playerState
        .dropFirst() // skip initial state
        .sink { newState in
            XCTAssertEqual(newState, .paused)
            expectation.fulfill()
        }

    // Simulate that a song was playing
    manager.playerState = .playing

    // Simulate interruption
    NotificationCenter.default.post(
        name: AVAudioSession.interruptionNotification,
        object: nil,
        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
    )

    wait(for: [expectation], timeout: 1.0)
    cancellable.cancel()
}

