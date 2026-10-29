import Foundation
import Combine
import AVKit

@MainActor final class PlaybackCoordinator:ObservableObject {
    @Published private(set) var movie:Movie?
    @Published private(set) var source:PlaybackSource?
    @Published private(set) var sources:[PlaybackSource]=[]
    @Published private(set) var player:AVPlayer?
    @Published var isExpanded=false
    @Published private(set) var countdown=0
    private weak var library:LocalLibrary?
    private weak var sync:CloudSync?
    private var timeObserver:Any?
    private var endObserver:NSObjectProtocol?
    private var nextTask:Task<Void,Never>?
    func configure(library:LocalLibrary,sync:CloudSync){self.library=library;self.sync=sync}
    func open(movie:Movie,source:PlaybackSource,sources:[PlaybackSource]) {
        if self.movie?.id == movie.id, self.source?.id == source.id, player != nil {isExpanded=true;return}
        closePlayer(); self.movie=movie; self.source=source; self.sources=sources
        start(source); isExpanded=true
    }
    func minimize(){save();sync?.saveProgressNow();isExpanded=false}
    func expand(){if player != nil {isExpanded=true}}
    func change(to next:PlaybackSource) {nextTask?.cancel();countdown=0;closePlayer();source=next;start(next)}
    func cancelNext(){nextTask?.cancel();nextTask=nil;countdown=0}
    func stop(){cancelNext();closePlayer();sync?.saveProgressNow();isExpanded=false;movie=nil;source=nil;sources=[]}
    private func start(_ source:PlaybackSource) {
        guard let url=URL(string:source.url) else{return}
        try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p=AVPlayer(url:url);player=p
        if let movie,let progress=library?.progress[movie.id],progress.episodeSlug==source.slug,progress.server==source.server,progress.position>0,progress.duration <= 0 || progress.position < progress.duration-1 {p.seek(to:CMTime(seconds:progress.position,preferredTimescale:600))}
        timeObserver=p.addPeriodicTimeObserver(forInterval:CMTime(seconds:5,preferredTimescale:600),queue:.main) { [weak self] _ in Task { @MainActor [weak self] in self?.save() } }
        endObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:p.currentItem,queue:.main) { [weak self] _ in Task { @MainActor [weak self] in self?.scheduleNext() } }
        p.play()
    }
    private func scheduleNext() {
        guard let source,let next=source.next(in:sources) else{return}
        cancelNext();countdown=5
        nextTask=Task { [weak self] in
            for value in (1...5).reversed() {guard !Task.isCancelled,let self else{return};self.countdown=value;try? await Task.sleep(for:.seconds(1))}
            guard !Task.isCancelled,let self else{return};self.countdown=0;self.change(to:next)
        }
    }
    private func save(){guard let player,let movie,let source,let library else{return};let position=player.currentTime().seconds;let duration=player.currentItem?.duration.seconds ?? 0;library.record(movie,source:source,position:position,duration:duration.isFinite ? duration : 0)}
    private func closePlayer(){guard let player else{return};save();if let timeObserver {player.removeTimeObserver(timeObserver);self.timeObserver=nil};if let endObserver {NotificationCenter.default.removeObserver(endObserver);self.endObserver=nil};player.pause();self.player=nil}
}
