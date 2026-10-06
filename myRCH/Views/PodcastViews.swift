import AVFoundation
import MediaPlayer
import SwiftUI

// MARK: - Model helpers

extension Podcast {
    /// Purple, like Apple Podcasts.
    static let color = Theme.proxy
}

extension PodcastEpisode {
    /// The artwork at a given size: the feed's is up to 3000 px, far more
    /// than a list row needs (the host resizes on request).
    func imageURL(size: Int) -> URL? {
        guard let imageURL, var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter { !["max-w", "max-h", "w", "h"].contains($0.name) }
        items += [URLQueryItem(name: "w", value: String(size)), URLQueryItem(name: "h", value: String(size))]
        components.queryItems = items
        return components.url ?? imageURL
    }

    /// e.g. "21 min", or "1 hr, 5 min".
    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        return Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// e.g. "23 Sep 2026 · 21 min".
    var detailText: String {
        [date.formatted(date: .abbreviated, time: .omitted), durationText].compactMap(\.self).joined(separator: " · ")
    }

    /// The show notes as paragraphs, list items marked with a bullet.
    var notesParagraphs: [String] {
        let marker = "\u{1}"
        let html = notesHTML
            // A list item's own paragraph would split its bullet from its text.
            .replacingOccurrences(of: "<li[^>]*>\\s*<p[^>]*>", with: "<li>", options: .regularExpression)
            .replacingOccurrences(of: "<li[^>]*>", with: marker + "• ", options: .regularExpression)
            .replacingOccurrences(of: "</p>|</li>|<br\\s*/?>|</h\\d>", with: marker, options: .regularExpression)
        return html.components(separatedBy: marker).map(HTMLText.plain).filter { !$0.isEmpty && $0 != "•" }
    }

    /// Fact sheets the notes link to, as the app has them, so they open here.
    var linkedSheets: [FactSheet] {
        let store = RCHContentStore.shared
        let all = FactSheet.Library.allCases.flatMap { store.factSheets[$0] ?? [] }
        let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        return HTMLText.matches(#"href="([^"]*/(?:kidsinfo/fact_sheets|teeninfo/fact-sheets)/[^"]+)""#, in: notesHTML)
            .compactMap { URL(string: $0[0]).flatMap { byKey[$0.lastPathComponent.lowercased()] } }
            .filter { seen.insert($0.key).inserted }
    }
}

// MARK: - Player

/// Plays one episode at a time, carrying on while the rest of the app is
/// browsed, in the background and with the phone locked. The lock screen,
/// Control Centre and headphones show the episode and control it.
@Observable
final class PodcastPlayer {
    static let shared = PodcastPlayer()

    private(set) var episode: PodcastEpisode?
    private(set) var isPlaying = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// True while the scrubber is held, so playback doesn't move it.
    var isScrubbing = false

    /// How far into an episode someone got, so they can finish it later.
    struct Progress: Codable, Hashable {
        /// Kept whole, so Discover can list it before the feed loads.
        var episode: PodcastEpisode
        var position: TimeInterval
        var duration: TimeInterval
        var updatedAt: Date

        var fraction: Double { duration > 0 ? min(position / duration, 1) : 0 }
        var remaining: TimeInterval { max(duration - position, 0) }

        /// e.g. "12 min left" or "1 hr 6 min left". Built by hand: the
        /// Australian format's "min." read oddly before "left".
        var remainingText: String {
            let minutes = max(Int((remaining / 60).rounded(.up)), 1)
            let hours = minutes / 60
            return hours > 0 ? "\(hours) hr \(minutes % 60) min left" : "\(minutes) min left"
        }
    }

    /// Started but unfinished episodes, by id.
    private(set) var progress: [String: Progress] = [:]

    /// Unfinished episodes, most recently listened to first.
    var inProgress: [Progress] {
        progress.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    @ObservationIgnored private static let progressKey = "podcastProgress"
    /// Under this, it hasn't really been started.
    @ObservationIgnored private static let minimumPosition: TimeInterval = 15
    /// Within this of the end (the credits), it counts as finished.
    @ObservationIgnored private static let finishedMargin: TimeInterval = 30
    /// Only this many are kept, the most recent.
    @ObservationIgnored private static let maximumKept = 10
    /// Where the position was last saved, so it's saved every few seconds
    /// while playing rather than twice a second.
    @ObservationIgnored private var savedPosition: TimeInterval = 0
    /// Where a resumed episode is seeking to. Until it gets there the player
    /// reports the start, which would otherwise overwrite the saved place.
    @ObservationIgnored private var pendingStart: TimeInterval?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.progressKey),
           let saved = try? JSONDecoder().decode([String: Progress].self, from: data) {
            progress = saved
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.update(time) }
        }
        // Follows the player itself, so a pause from elsewhere (a phone
        // call, headphones unplugged, another app's audio) shows in the app.
        statusObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor [weak self] in self?.setPlaying(playing) }
        }
        setUpRemoteCommands()
    }

    func isCurrent(_ episode: PodcastEpisode) -> Bool { self.episode?.id == episode.id }

    /// Plays or pauses the episode, starting it if another one's loaded.
    func toggle(_ episode: PodcastEpisode) {
        guard isCurrent(episode) else { return play(episode) }
        if isPlaying { pause() } else { resume() }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: min(max(elapsed + seconds, 0), duration > 0 ? duration : .infinity))
    }

    func seek(to seconds: TimeInterval) {
        pendingStart = nil
        elapsed = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlaying()
        saveProgress()
    }

    /// Takes an episode off "Finish Where You Left Off".
    func markFinished(_ episode: PodcastEpisode) {
        progress[episode.id] = nil
        storeProgress()
    }

    private func pause() {
        player.pause()
        setPlaying(false)
    }

    private func resume() {
        // Back on after another app took the audio.
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        setPlaying(true)
    }

    private func play(_ episode: PodcastEpisode) {
        // Spoken audio, so it plays with the silent switch on, and in the
        // background with the "audio" background mode.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: episode.audioURL)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setPlaying(false)
                self?.seek(to: 0)
                self?.markFinished(episode)
            }
        }
        // Picks up where it was left, if it was.
        let start = progress[episode.id]?.position ?? 0
        self.episode = episode
        elapsed = start
        savedPosition = start
        // The saved or feed's length until the file's own is known.
        duration = progress[episode.id]?.duration ?? episode.duration ?? 0
        artwork = nil
        player.replaceCurrentItem(with: item)
        pendingStart = start > 0 ? start : nil
        if start > 0 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        player.play()
        setPlaying(true)
        Task { await loadArtwork(for: episode) }
    }

    private func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        updateNowPlaying()
        // Saved on every pause, including a call or the app being closed
        // from the lock screen.
        if !playing { saveProgress() }
    }

    private func update(_ time: CMTime) {
        if let length = player.currentItem?.duration.seconds, length.isFinite, length > 0, length != duration {
            duration = length
            updateNowPlaying()
        }
        guard !isScrubbing, time.seconds.isFinite else { return }
        if let pendingStart {
            guard abs(time.seconds - pendingStart) < 3 else { return }
            self.pendingStart = nil
        }
        elapsed = time.seconds
        if abs(elapsed - savedPosition) >= 5 { saveProgress() }
    }

    // MARK: Progress

    /// Records the current episode's position, or clears it once it's
    /// nearly over. Barely started ones aren't listed.
    private func saveProgress() {
        guard let episode, duration > 0 else { return }
        savedPosition = elapsed
        if duration - elapsed <= Self.finishedMargin {
            progress[episode.id] = nil
        } else if elapsed >= Self.minimumPosition {
            progress[episode.id] = Progress(episode: episode, position: elapsed, duration: duration, updatedAt: .now)
        } else {
            // Scrubbed back to the start.
            progress[episode.id] = nil
        }
        storeProgress()
    }

    private func storeProgress() {
        let kept = inProgress.prefix(Self.maximumKept)
        if kept.count < progress.count {
            progress = Dictionary(uniqueKeysWithValues: kept.map { ($0.episode.id, $0) })
        }
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: Self.progressKey)
    }

    // MARK: Lock screen

    /// Play, pause, skip and scrub from the lock screen, Control Centre and
    /// headphones.
    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.episode != nil else { return .noActionableNowPlayingItem }
                self.resume()
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pause()
                return .success
            }
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let episode = self.episode else { return .noActionableNowPlayingItem }
                self.toggle(episode)
                return .success
            }
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.skip(by: -15)
                return .success
            }
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.skip(by: 30)
                return .success
            }
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            return MainActor.assumeIsolated {
                self?.seek(to: position)
                return .success
            }
        }
    }

    /// The episode's title, artwork and position, for the lock screen. The
    /// system moves the position along itself from the rate.
    private func updateNowPlaying() {
        guard let episode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: "The Royal Children's Hospital, Melbourne",
            MPMediaItemPropertyAlbumTitle: Podcast.title,
            MPMediaItemPropertyMediaType: MPMediaType.podcast.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for episode: PodcastEpisode) async {
        guard let url = episode.imageURL(size: 600),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data), isCurrent(episode) else { return }
        // Called off the main thread by the system, so it only uses the
        // image it's handed.
        artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable [image] _ in image }
        updateNowPlaying()
    }
}

// MARK: - List

/// Every episode, newest first, searchable by title or notes.
struct PodcastListView: View {
    @State private var store = RCHContentStore.shared
    @State private var searchText = ""

    private var episodes: [PodcastEpisode] {
        guard !searchText.isEmpty else { return store.podcastEpisodes }
        return store.podcastEpisodes.filter {
            $0.title.localizedStandardContains(searchText) || $0.summary.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(episodes) { episode in
                NavigationLink { PodcastEpisodeView(episode: episode) } label: { ContentRow(episode: episode) }
            }
            if store.podcastEpisodes.isEmpty, store.podcastError == nil {
                ForEach(0..<6, id: \.self) { _ in ContentRow.placeholder }
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.podcastEpisodes.isEmpty, let error = store.podcastError {
                ContentUnavailableView("Couldn't load the podcast", systemImage: "wifi.exclamationmark",
                                       description: Text(error))
            } else if episodes.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Podcast")
        .searchable(text: $searchText, prompt: "Search episodes")
        .refreshable { await store.loadPodcast(force: true) }
        .task { await store.loadPodcast() }
        .toolbar { PodcastAppsMenu() }
    }
}

/// Opens the show in Apple Podcasts or Spotify, to subscribe there.
private struct PodcastAppsMenu: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Listen Elsewhere", systemImage: "ellipsis") {
                Link(destination: Podcast.applePodcastsURL) {
                    Label("Open in Apple Podcasts", systemImage: "apple.podcasts.pages")
                }
                Link(destination: Podcast.spotifyURL) {
                    Label("Open in Spotify", systemImage: "music.note")
                }
                Link(destination: Podcast.pageURL) {
                    Label("Open on RCH Website", systemImage: "safari")
                }
            }
        }
    }
}

// MARK: - Episode

/// An episode's artwork, player and show notes.
struct PodcastEpisodeView: View {
    let episode: PodcastEpisode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    AsyncImage(url: episode.imageURL(size: 600)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: Podcast.systemImage)
                                .font(.system(size: 60))
                                .foregroundStyle(Podcast.color)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Podcast.color.opacity(0.14))
                        }
                    }
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text(episode.title)
                            .font(.title2.bold())
                        Text(episode.detailText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    PodcastControls(episode: episode)
                }
                .frame(maxWidth: .infinity)

                let sheets = episode.linkedSheets
                if !sheets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fact Sheets in This Episode")
                            .font(.title3.bold())
                        ForEach(sheets) { sheet in
                            NavigationLink { FactSheetArticleView(sheet: sheet) } label: { ContentRow(sheet: sheet) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Episode Notes")
                        .font(.title3.bold())
                    ForEach(Array(episode.notesParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Podcast")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: Podcast.pageURL, subject: Text(episode.title))
            }
        }
    }
}

/// Play/pause, skip back 15 and forward 30, and a scrubber once playing.
private struct PodcastControls: View {
    let episode: PodcastEpisode

    @State private var player = PodcastPlayer.shared

    var body: some View {
        let isCurrent = player.isCurrent(episode)
        let isPlaying = isCurrent && player.isPlaying
        VStack(spacing: 14) {
            if isCurrent {
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { player.elapsed }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 1)) { editing in
                        player.isScrubbing = editing
                    }
                    .tint(Podcast.color)
                    .accessibilityLabel("Position")
                    .accessibilityValue(Duration.seconds(player.elapsed).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
                    HStack {
                        Text(Self.time(player.elapsed))
                        Spacer()
                        Text("-" + Self.time(max(player.duration - player.elapsed, 0)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
            } else if let saved = player.progress[episode.id] {
                // Not loaded yet, but started before: where play picks up.
                VStack(spacing: 6) {
                    ProgressView(value: saved.fraction)
                        .tint(Podcast.color)
                    Text(saved.remainingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 40) {
                Button("Back 15 Seconds", systemImage: "gobackward.15") { player.skip(by: -15) }
                    .font(.title)
                    .disabled(!isCurrent)
                Button(isPlaying ? "Pause" : (!isCurrent && player.progress[episode.id] != nil ? "Resume" : "Play"),
                       systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                    player.toggle(episode)
                }
                .font(.system(size: 64))
                Button("Forward 30 Seconds", systemImage: "goforward.30") { player.skip(by: 30) }
                    .font(.title)
                    .disabled(!isCurrent)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(Podcast.color)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }

    /// e.g. "4:05", or "1:02:10".
    private static func time(_ seconds: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: pattern))
    }
}

// MARK: - Finish where you left off

/// Discover's list of started episodes, most recent first, each with how
/// much is left and a button to carry on without opening it. Hidden when
/// there are none.
struct PodcastResumeSection<Header: View>: View {
    @ViewBuilder let header: () -> Header

    @State private var player = PodcastPlayer.shared

    var body: some View {
        let started = Array(player.inProgress.prefix(3))
        if !started.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header()
                ForEach(Array(started.enumerated()), id: \.element.episode.id) { index, saved in
                    if index > 0 { Divider().padding(.leading, 80) }
                    PodcastResumeRow(saved: saved)
                }
            }
        }
    }
}

/// A started episode: artwork, title, a bar of how far in, and play/pause.
private struct PodcastResumeRow: View {
    let saved: PodcastPlayer.Progress

    @State private var player = PodcastPlayer.shared

    var body: some View {
        let episode = saved.episode
        let isPlaying = player.isCurrent(episode) && player.isPlaying
        HStack(spacing: 14) {
            NavigationLink { PodcastEpisodeView(episode: episode) } label: {
                HStack(spacing: 14) {
                    AsyncImage(url: episode.imageURL(size: 200)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: Podcast.systemImage)
                                .font(.title)
                                .foregroundStyle(Podcast.color)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Podcast.color.opacity(0.14))
                        }
                    }
                    .frame(width: 66, height: 66)
                    .clipShape(.rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        ProgressView(value: saved.fraction)
                            .tint(Podcast.color)
                            .accessibilityHidden(true)
                        Text(saved.remainingText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(isPlaying ? "Pause" : "Resume", systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                player.toggle(episode)
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 36))
            .foregroundStyle(Podcast.color)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contextMenu {
            Button("Mark as Finished", systemImage: "checkmark.circle") { player.markFinished(episode) }
        }
    }
}
