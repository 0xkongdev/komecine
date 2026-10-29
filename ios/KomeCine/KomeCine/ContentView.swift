import SwiftUI

private enum Design {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let surface = Color(red: 0.09, green: 0.105, blue: 0.12)
    static let accent = Color(red: 0.22, green: 0.86, blue: 0.79)
}

struct ContentView: View {
    @StateObject private var library = LocalLibrary()
    @StateObject private var auth = AuthManager()
    @StateObject private var sync = CloudSync()
    @StateObject private var playback = PlaybackCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Trang chủ", systemImage:"house.fill") }
            NavigationStack { SearchView() }.tabItem { Label("Khám phá", systemImage:"magnifyingglass") }
            NavigationStack { LibraryView() }.tabItem { Label("Thư viện", systemImage:"square.stack.fill") }
        }
        .environmentObject(library).environmentObject(auth).environmentObject(sync).environmentObject(playback).tint(Design.accent).preferredColorScheme(.dark)
            .overlay(alignment:.bottom) { if let movie=playback.movie,playback.player != nil && !playback.isExpanded { HStack { Button {playback.expand()} label: { HStack { Image(systemName:"play.rectangle.fill"); VStack(alignment:.leading) {Text(movie.name).lineLimit(1).font(.caption.bold());Text("Đang phát").font(.caption2).foregroundStyle(.secondary)}; Spacer() } }; Button {playback.stop()} label: {Image(systemName:"xmark").padding(10)} }.padding(.horizontal,12).padding(.vertical,8).background(Design.surface,in:RoundedRectangle(cornerRadius:10)).padding(.horizontal,8).padding(.bottom,52) } }
            .fullScreenCover(isPresented:$playback.isExpanded) { PlayerScreen().environmentObject(playback) }
            .onAppear { sync.configure(library:library,auth:auth); playback.configure(library:library,sync:sync); if auth.token != nil { sync.activate(auth.userID,previousID:nil) } }
            .onChange(of: auth.userID) { oldValue, newValue in sync.activate(newValue,previousID:oldValue) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await sync.synchronize() } } else if phase == .background { sync.saveProgressNow() } }
    }
}

private struct Poster: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default: ZStack { Design.surface; Image(systemName:"film").font(.title2).foregroundStyle(.white.opacity(0.23)) }
            }
        }
        .clipped()
    }
}

private struct MovieCard: View {
    let movie: Movie
    var body: some View {
        NavigationLink { MovieDetailView(movie:movie) } label: {
            VStack(alignment:.leading,spacing:7) {
                Poster(url:movie.posterURL ?? movie.backdropURL).frame(width:122,height:174).clipShape(RoundedRectangle(cornerRadius:10))
                Text(movie.name).font(.system(size:13,weight:.semibold)).lineLimit(2).multilineTextAlignment(.leading).frame(width:122,alignment:.leading)
                if let year=movie.year { Text(String(year)).font(.caption2).foregroundStyle(.secondary) }
            }.foregroundStyle(.white).frame(width:122,alignment:.topLeading)
        }.buttonStyle(.plain)
    }
}

private struct MovieShelf: View {
    let title: String
    let subtitle: String
    let movies: [Movie]
    var body: some View {
        if !movies.isEmpty {
            VStack(alignment:.leading,spacing:14) {
                HStack(alignment:.bottom) { VStack(alignment:.leading,spacing:4) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer() }
                    .padding(.horizontal,20)
                ScrollView(.horizontal,showsIndicators:false) { LazyHStack(alignment:.top,spacing:12) { ForEach(movies) { MovieCard(movie:$0) } }.padding(.horizontal,20) }
            }.padding(.top,26)
        }
    }
}

private struct RankingShelf: View {
    let title: String
    let items: [RankedMovie]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment:.leading,spacing:14) {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.title3.bold())
                    Text("Theo RoPhim · Hôm nay").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal,20)
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(alignment:.top,spacing:12) {
                        ForEach(items) { item in
                            NavigationLink { RankingDetailView(item:item) } label: {
                                VStack(alignment:.leading,spacing:7) {
                                    ZStack(alignment:.bottomLeading) {
                                        Poster(url:item.movie.posterURL ?? item.movie.backdropURL).frame(width:122,height:174).clipShape(RoundedRectangle(cornerRadius:10))
                                        Text(String(item.rank)).font(.system(size:38,weight:.black)).foregroundStyle(.white).shadow(color:.black,radius:4).padding(.leading,7).padding(.bottom,2)
                                    }
                                    Text(item.movie.name).font(.system(size:13,weight:.semibold)).lineLimit(2).multilineTextAlignment(.leading).frame(width:122,alignment:.leading)
                                    if let year=item.movie.year { Text(String(year)).font(.caption2).foregroundStyle(.secondary) }
                                }.foregroundStyle(.white).frame(width:122,alignment:.topLeading)
                            }.buttonStyle(.plain).accessibilityIdentifier("ranking-\(item.type)-\(item.rank)")
                        }
                    }.padding(.horizontal,20)
                }
            }.padding(.top,26)
        }
    }
}

private struct RankingDetailView: View {
    let item: RankedMovie
    @State private var detail: MovieDetail?
    @State private var error: String?
    var body: some View {
        Group {
            if let detail { MovieDetailView(movie:detail.movie, initialDetail:detail) }
            else if let error {
                ContentUnavailableView { Label(item.movie.name,systemImage:"film") } description: { Text(error) } actions: { Button("Thử lại") { Task { await load() } } }
            } else { ProgressView("Đang tìm nguồn phim…") }
        }.background(Design.background.ignoresSafeArea()).task { await load() }
    }
    private func load() async {
        error=nil
        do { detail=try await APIClient.shared.resolveRanking(item) }
        catch { self.error=error.localizedDescription }
    }
}

private struct Hero: View {
    let movie: Movie
    let width: CGFloat
    var featured: RankedMovie? = nil
    @EnvironmentObject private var library: LocalLibrary
    @EnvironmentObject private var playback: PlaybackCoordinator
    @State private var isOpening = false
    @State private var playbackError: String?
    var body: some View {
        ZStack(alignment:.bottomLeading) {
            Poster(url:movie.backdropURL ?? movie.posterURL).frame(width:width,height:400).clipped().accessibilityHidden(true)
            LinearGradient(colors:[.clear,Design.background.opacity(0.3),Design.background],startPoint:.center,endPoint:.bottom).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:10) {
                Text("NỔI BẬT HÔM NAY").font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(Design.accent)
                if featured != nil { Text("Theo RoPhim").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                Text(movie.name).font(.system(size:31,weight:.bold)).lineLimit(2)
                Text([movie.originName,movie.year.map(String.init)].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:"  ·  ")).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                HStack(spacing:14) {
                    Button { Task { await play() } } label: {
                        Label(isOpening ? "Đang tải" : "Xem ngay",systemImage:"play.fill").font(.subheadline.bold()).padding(.horizontal,18).padding(.vertical,11).background(Design.accent,in:Capsule()).foregroundStyle(.black)
                    }.disabled(isOpening)
                    NavigationLink {
                        if let featured { RankingDetailView(item:featured) } else { MovieDetailView(movie:movie) }
                    } label: { Text("Chi tiết").font(.subheadline.bold()).foregroundStyle(.white) }
                }.padding(.top,5)
                if let playbackError { Text(playbackError).font(.caption).foregroundStyle(.white) }
            }.padding(.horizontal,20).padding(.bottom,20)
        }.frame(width:width,height:400).clipped().foregroundStyle(.white).buttonStyle(.plain)
    }
    private func play() async {
        isOpening = true
        playbackError = nil
        defer { isOpening = false }
        do {
            let detail: MovieDetail
            if let featured { detail = try await APIClient.shared.resolveRanking(featured) }
            else { detail = try await APIClient.shared.detail(movie.slug) }
            let playableMovie = detail.movie
            let progress = library.progress[playableMovie.id]
            let source = detail.sources.first { $0.slug == progress?.episodeSlug && $0.server == progress?.server } ?? detail.sources.first
            guard let source else { playbackError = "Phim này hiện chưa có nguồn phát."; return }
            playback.open(movie:playableMovie,source:source,sources:detail.sources)
        } catch { playbackError = error.localizedDescription }
    }
}

private struct FeaturedCarousel: View {
    let items: [RankedMovie]
    let width: CGFloat
    @State private var selected = 0
    var body: some View {
        TabView(selection:$selected) {
            ForEach(Array(items.enumerated()),id:\.element.id) { index,item in
                Hero(movie:item.movie,width:width,featured:item).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode:.never))
        .frame(width:width,height:400)
        .overlay(alignment:.topTrailing) {
            if items.count > 1 { Text("\(min(selected + 1,items.count)) / \(items.count)").font(.caption.bold()).padding(.horizontal,10).padding(.vertical,5).background(.black.opacity(0.45),in:Capsule()).padding(16).accessibilityLabel("Phim nổi bật \(min(selected + 1,items.count)) trên \(items.count)") }
        }
        .accessibilityIdentifier("featured-carousel")
        .onChange(of:items.map(\.id)) { _,_ in selected=0 }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var library: LocalLibrary
    @State private var latest:[Movie]=[]
    @State private var series:[Movie]=[]
    @State private var movies:[Movie]=[]
    @State private var animation:[Movie]=[]
    @State private var featured:[RankedMovie]=[]
    @State private var rankings:Rankings?
    @State private var rankingsUnavailable=false
    @State private var loading=true
    @State private var error:String?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing:0) {
                    if !featured.isEmpty { FeaturedCarousel(items:featured,width:geometry.size.width) }
                    else if let first=latest.first { Hero(movie:first,width:geometry.size.width) }
                    else if loading { ProgressView().frame(height:300) }
                    else if let error { ContentUnavailableView { Label("Không tải được phim",systemImage:"wifi.exclamationmark") } description: { Text(error) } actions: { Button("Thử lại") { Task { await load() } } }.frame(height:300) }
                    MovieShelf(title:"Tiếp tục xem",subtitle:"Phim bạn đang theo dõi",movies:library.recent)
                    RankingShelf(title:"Top phim bộ hôm nay",items:rankings?.series ?? [])
                    RankingShelf(title:"Top phim lẻ hôm nay",items:rankings?.movies ?? [])
                    if rankingsUnavailable && rankings == nil {
                        HStack { Text("Chưa tải được bảng xếp hạng RoPhim.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Thử lại") { Task { await loadRankings() } }.font(.caption.bold()) }.padding(.horizontal,20).padding(.top,20)
                    }
                    MovieShelf(title:"Mới cập nhật",subtitle:"Những câu chuyện vừa lên sóng",movies:latest)
                    MovieShelf(title:"Phim bộ",subtitle:"Cuốn hút qua từng tập",movies:series)
                    MovieShelf(title:"Phim lẻ",subtitle:"Chọn một bộ phim cho hôm nay",movies:movies)
                    MovieShelf(title:"Hoạt hình",subtitle:"Khám phá thế giới mới",movies:animation)
                }.frame(width:geometry.size.width).padding(.bottom,30)
            }.refreshable { await load() }
        }.background(Design.background.ignoresSafeArea())
            .navigationTitle("KomeCine").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.principal) { (Text("KOME").foregroundColor(Design.accent) + Text("CINE").foregroundColor(.white)).font(.system(size:17,weight:.black)) } }
            .task { if latest.isEmpty { await load() } }
    }
    private func load() async {
        loading=true; error=nil
        async let rankingLoad: Void = loadRankings()
        async let featuredLoad = try? APIClient.shared.featured()
        do { latest=try await APIClient.shared.latest() } catch { self.error=error.localizedDescription }
        async let a = try? APIClient.shared.browse("phim-bo")
        async let b = try? APIClient.shared.browse("phim-le")
        async let c = try? APIClient.shared.browse("hoat-hinh")
        series = await a ?? []; movies = await b ?? []; animation = await c ?? []
        if let newFeatured = await featuredLoad, !newFeatured.isEmpty { featured=newFeatured }
        _ = await rankingLoad; loading=false
    }
    private func loadRankings() async {
        do { rankings = try await APIClient.shared.rankings(); rankingsUnavailable=false }
        catch { rankingsUnavailable=true }
    }
}

private struct SearchView: View {
    @State private var query=""
    @State private var results:[Movie]=[]
    @State private var kind="phim-moi"
    @State private var category=""
    @State private var country=""
    @State private var year=""
    @State private var filters=Filters(categories:[],countries:[])
    @State private var page=1
    @State private var loading=false
    @State private var searchGeneration=UUID()
    @State private var error:String?
    private let columns=[GridItem(.adaptive(minimum:115),spacing:12)]
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Tìm câu chuyện\nbạn yêu thích.").font(.system(size:28,weight:.bold)).padding(.top,12)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:8) {
                    filterMenu("Loại phim",selection:$kind,options:[FilterItem(name:"Tất cả",slug:"phim-moi"),FilterItem(name:"Phim bộ",slug:"phim-bo"),FilterItem(name:"Phim lẻ",slug:"phim-le"),FilterItem(name:"Hoạt hình",slug:"hoat-hinh")])
                    filterMenu("Thể loại",selection:$category,options:[FilterItem(name:"Tất cả",slug:"")]+filters.categories)
                    filterMenu("Quốc gia",selection:$country,options:[FilterItem(name:"Tất cả",slug:"")]+filters.countries)
                    filterMenu("Năm",selection:$year,options:[FilterItem(name:"Tất cả",slug:"")]+(2000...Calendar.current.component(.year,from:Date())).reversed().map{FilterItem(name:String($0),slug:String($0))})
                }}
                if loading && results.isEmpty { ProgressView().frame(maxWidth:.infinity,minHeight:180) }
                else if let error { ContentUnavailableView("Không thể tải phim",systemImage:"wifi.exclamationmark",description:Text(error)) }
                else if results.isEmpty { ContentUnavailableView("Chưa có kết quả",systemImage:"magnifyingglass",description:Text("Thử một từ khóa hoặc bộ lọc khác.")) }
                LazyVGrid(columns:columns,alignment:.leading,spacing:20) { ForEach(results) { MovieCard(movie:$0) } }
                if !results.isEmpty { Button("Xem thêm") { let generation=searchGeneration; Task { await loadMore(generation:generation) } }.frame(maxWidth:.infinity).padding().disabled(loading) }
            }.padding(.horizontal,20).padding(.bottom,30)
        }.background(Design.background.ignoresSafeArea()).navigationTitle("Khám phá").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$query,prompt:"Tìm phim, diễn viên...")
            .task { filters = (try? await APIClient.shared.filters()) ?? filters }
            .task(id:"\(query)|\(kind)|\(category)|\(country)|\(year)") { let generation=UUID(); searchGeneration=generation; loading=false; page=1; results=[]; try? await Task.sleep(for:.milliseconds(350)); guard !Task.isCancelled, generation == searchGeneration else{return}; await loadMore(generation:generation) }
    }
    private func filterMenu(_ title:String,selection:Binding<String>,options:[FilterItem])->some View {
        Menu { Picker(title,selection:selection) { ForEach(options) { Text($0.name).tag($0.slug) } } } label: { HStack(spacing:5) { Text(options.first(where:{$0.slug==selection.wrappedValue && !$0.slug.isEmpty})?.name ?? title); Image(systemName:"chevron.down").font(.caption2) }.font(.caption.bold()).padding(.horizontal,12).padding(.vertical,9).background(Design.surface,in:Capsule()) }
    }
    private func loadMore(generation:UUID) async {
        guard !loading, generation == searchGeneration else{return}
        loading=true; error=nil
        let requestPage=page, requestQuery=query, requestKind=kind, requestCategory=category, requestCountry=country, requestYear=year
        defer { if generation == searchGeneration {loading=false} }
        do {
            let next = requestQuery.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? try await APIClient.shared.browse(requestKind,page:requestPage,category:requestCategory,country:requestCountry,year:requestYear) : try await APIClient.shared.search(requestQuery,page:requestPage,category:requestCategory,country:requestCountry,year:requestYear)
            guard !Task.isCancelled, generation == searchGeneration else{return}
            results += next.filter { movie in !results.contains(where:{$0.id==movie.id}) }; page=requestPage+1
        } catch { if !Task.isCancelled && generation == searchGeneration { self.error=error.localizedDescription } }
    }
}

private struct LibraryView: View {
    @EnvironmentObject private var library:LocalLibrary
    @EnvironmentObject private var auth:AuthManager
    @EnvironmentObject private var sync:CloudSync
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:0) {
            Text("Thư viện của bạn").font(.largeTitle.bold()).padding(.horizontal,20).padding(.top,12)
            Text("Mọi câu chuyện bạn muốn giữ lại.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal,20).padding(.top,5)
            MovieShelf(title:"Tiếp tục xem",subtitle:"Quay lại nơi bạn dừng",movies:library.recent)
            MovieShelf(title:"Yêu thích",subtitle:"Danh sách dành riêng cho bạn",movies:library.favorites)
            if library.recent.isEmpty && library.favorites.isEmpty { ContentUnavailableView("Thư viện còn trống",systemImage:"heart",description:Text("Lưu phim yêu thích hoặc bắt đầu xem để tìm lại tại đây.")) }
            VStack(alignment:.leading,spacing:8) { Text("Tài khoản").font(.headline); if let name = auth.displayName { Text(name).font(.subheadline); Button("Đăng xuất") { Task { await auth.signOut() } } } else { Text("Đăng nhập để sử dụng tài khoản của bạn.").font(.subheadline).foregroundStyle(.secondary); Button("Đăng nhập bằng Google") { Task { await auth.signIn() } }.disabled(auth.busy) }; if let message=auth.message ?? sync.error { Text(message).font(.caption).foregroundStyle(.secondary) } else if sync.isSyncing { Text("Đang đồng bộ…").font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(Design.surface,in:RoundedRectangle(cornerRadius:14)).padding(20)
        }}.background(Design.background.ignoresSafeArea()).navigationTitle("Thư viện").navigationBarTitleDisplayMode(.inline)
    }
}

private struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject private var library:LocalLibrary
    @EnvironmentObject private var playback:PlaybackCoordinator
    @State private var detail:MovieDetail?
    @State private var error:String?
    init(movie: Movie, initialDetail: MovieDetail? = nil) { self.movie=movie; _detail=State(initialValue:initialDetail) }
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:15) {
            ZStack(alignment:.bottom) { Poster(url:movie.backdropURL ?? movie.posterURL).frame(height:260); LinearGradient(colors:[.clear,Design.background],startPoint:.center,endPoint:.bottom) }.frame(height:260)
            VStack(alignment:.leading,spacing:14) {
                Text(movie.name).font(.title.bold()); if !movie.originName.isEmpty { Text(movie.originName).foregroundStyle(.secondary) }
                if let detail {
                    Text(([detail.quality,detail.language,detail.duration]+detail.categories).filter{!$0.isEmpty}.joined(separator:"  ·  ")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { if let source=resumeSource(detail) {playback.open(movie:movie,source:source,sources:detail.sources)} } label: { Label(library.progress[movie.id] == nil ? "Xem ngay" : "Tiếp tục xem",systemImage:"play.fill").font(.headline).frame(maxWidth:.infinity).padding(13).background(Design.accent,in:RoundedRectangle(cornerRadius:10)).foregroundStyle(.black) }.disabled(detail.sources.isEmpty)
                        Button { library.toggleFavorite(movie) } label: { Image(systemName:library.favorites.contains(where:{$0.id==movie.id}) ? "heart.fill" : "heart").font(.title3).frame(width:48,height:48).background(Design.surface,in:RoundedRectangle(cornerRadius:10)) }
                    }
                    if !detail.description.isEmpty { Text(detail.description.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4) }
                    Text("Tập phim").font(.title3.bold()).padding(.top,8)
                    if detail.sources.isEmpty { Text("Phim này hiện chưa có nguồn phát.").foregroundStyle(.secondary) }
                    ForEach(Array(Set(detail.sources.map(\.server))).sorted(),id:\.self) { server in
                        Text(server).font(.subheadline.bold()).foregroundStyle(Design.accent)
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:76))],spacing:8) {
                            ForEach(detail.sources.filter{$0.server==server}) { source in Button(source.name.isEmpty ? source.slug : source.name) { playback.open(movie:movie,source:source,sources:detail.sources) }.font(.caption.bold()).frame(maxWidth:.infinity,minHeight:42).background(Design.surface,in:RoundedRectangle(cornerRadius:8)) }
                        }
                    }
                } else if let error { Text(error).foregroundStyle(.secondary); Button("Thử lại") { Task { await load() } } }
                else { ProgressView().frame(maxWidth:.infinity,minHeight:100) }
            }.padding(.horizontal,20)
        }.padding(.bottom,35)}.background(Design.background.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline)
            .task { if detail == nil { await load() } }
    }
    private func load() async { error=nil; do { detail=try await APIClient.shared.detail(movie.slug) } catch { self.error=error.localizedDescription } }
    private func resumeSource(_ detail:MovieDetail)->PlaybackSource? { if let progress=library.progress[movie.id], let source=detail.sources.first(where:{$0.slug==progress.episodeSlug && $0.server==progress.server}) { return source }; return detail.sources.first }
}
