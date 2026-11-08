import SwiftUI
import NXCore
import NXModel
import NXLauncher

/// The Library page of the launcher: the hero, the collection row and the status line of a game. A move out of LauncherView.swift
/// (LNPANDY/NX2Apple#387), the state stays in LauncherView.
extension LauncherView {
    var libraryPage: some View {
        GeometryReader { geometry in
            if library.games.isEmpty {
                emptyLibrary
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let game = heroGame {
                            // While the panel is open the hero is laid out at its size with the panel closed (the panel's
                            // width given back, the height it had) and scaled down to fit: same crop, same title, only smaller
                            let editing = artworkEditor != nil
                            let full = CGSize(width: geometry.size.width + (editing ? ArtworkPanel.width + 1 : 0),
                                              height: editing ? closedHeroHeight : max(240, geometry.size.height - collectionHeight))
                            let scale = min(1, geometry.size.width / full.width)
                            hero(game, width: full.width, height: full.height)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: geometry.size.width, height: full.height * scale, alignment: .topLeading)
                                .opacity(dimmed(.hero))
                                .onAppear { closedHeroHeight = full.height; artworkHeroAspect = full.width / full.height }
                                .onChange(of: full) { size in
                                    if !editing { closedHeroHeight = size.height }
                                    artworkHeroAspect = size.width / size.height
                                }
                        }
                        // The hero takes what the collection leaves: the row's height grows with the window's width (its cards
                        // do, up to 300 pt), so a fixed share left a fullscreen window's cards cut off at the bottom
                        collection(width: geometry.size.width)
                            .background(GeometryReader { g in Color.clear.preference(key: CollectionHeightKey.self, value: g.size.height) })
                            .opacity(dimmed(.thumbnail))
                    }
                }
                .onPreferenceChange(CollectionHeightKey.self) { h in if h > 0, abs(h - collectionHeight) > 0.5 { collectionHeight = h } }
                .animation(.easeOut(duration: 0.18), value: artworkSlot)
            }
        }
    }

    var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "gamecontroller").font(.system(size: 44, weight: .light))
                .foregroundStyle(LauncherPalette.cream)
            Text(loc.t("library.welcome")).font(.manrope(54, .bold)).tracking(-1.8)
            Text(loc.t("library.welcomeNote")).font(.manrope(17)).foregroundStyle(.secondary)
                .frame(maxWidth: 490, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button { newBuild() } label: {
                Label(loc.t("library.firstBuild"), systemImage: "plus")
                    .font(.manrope(16, .semibold))
                    .padding(.horizontal, 24).padding(.vertical, 15)
                    .foregroundStyle(.black).background(LauncherPalette.cream, in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 8)
            Button(action: chooseLibraryFolder) {
                Label(loc.t("library.chooseFolder"), systemImage: "folder")
                    .font(.manrope(14)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
            Spacer()
            Text(loc.t("library.localNote")).font(.manrope(12)).foregroundStyle(.secondary)
        }
        .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    func hero(_ game: LibraryGame, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = heroArtwork?.id == game.id ? heroArtwork?.image : artwork[game.id] {
                ArtworkFill(image: image, focus: displayed(game).artwork.focus(for: .hero))
                    .frame(width: width, height: height).clipped()
            } else {
                LauncherPalette.surface
                Image(systemName: "gamecontroller").font(.system(size: 160, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.05))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(60)
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.25),
                                   .init(color: .black.opacity(0.25), location: 0.45),
                                   .init(color: LauncherPalette.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.24), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    status(game, prominent: true)
                    if toolsAge.older.contains(game.id) && !(m.running && activeBuildID == game.id) {
                        Button { configureBuild(game) } label: {
                            Label(loc.t("library.rebuildShort"), systemImage: "arrow.clockwise")
                                .font(.manrope(12, .semibold)).foregroundStyle(LauncherPalette.cream)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .overlay(Capsule().strokeBorder(LauncherPalette.cream.opacity(0.35)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain).disabled(m.running || game.inputs["base", default: []].isEmpty)
                        .help(loc.t("library.olderToolsHelp"))
                        .padTarget("hero.rebuild", scope: "main", radius: 12) { if !m.running { configureBuild(game) } }
                    }
                }
                Text(game.name).font(.manrope(min(68, width * 0.052), .heavy))
                    .tracking(-1.6).lineLimit(2).shadow(color: .black.opacity(0.25), radius: 12)
                HStack(spacing: 18) {
                    Button { primaryAction(game) } label: {
                        LauncherHeroActionLabel(
                            title: game.primary == .play ? loc.t("library.play")
                                : (game.primary == .openOnDevice ? String(format: loc.t("dev.open"), devices.deviceName(game.installedDevice))
                                   : loc.t("library.newBuild")),
                            symbol: game.primary == .play ? "play.fill" : (game.primary == .openOnDevice ? "iphone" : "hammer.fill"))
                    }
                    .buttonStyle(.plain).disabled(launching || (m.running && !game.isReady) || artworkEditor != nil)
                    .keyboardShortcut(.return, modifiers: [])
                    .padTarget("hero.play", scope: "main", radius: 30) { if !launching { primaryAction(game) } }
                    if game.isReady {
                        Button { optionsFor = game.id } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 17))
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.10), in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain).help(loc.t("launch.title")).accessibilityLabel(loc.t("launch.title"))
                        .padTarget("hero.options", scope: "main", radius: 24) { optionsFor = game.id }
                    }
                    Button { manageOpenFor = manageOpenFor == nil ? game.id : nil } label: { ManageButtonLabel(title: loc.t("library.manage")) }
                        .buttonStyle(.plain).accessibilityLabel(loc.t("library.manage"))
                        .anchorPreference(key: ManageAnchorKey.self, value: .bounds) { $0 }
                        .padTarget("hero.manage", scope: "main", radius: 12) { manageOpenFor = game.id }
                }
                // A free Apple ID's provisioning profile lasts 7 days. Say when this app's runs out, and offer the
                // re-sign at any time: renewing early (before a trip, say) is as valid as renewing just in time.
                if game.onDevice && !game.isOlderIOSBuild {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal").font(.system(size: 12))
                            .foregroundStyle(LauncherPalette.cream.opacity(0.7))
                        Text(signatureExpiry[game.id].map { AppSignature.describe($0, loc.t) } ?? loc.t("dev.expiryUnknown"))
                            .font(.manrope(12.5))
                            .foregroundStyle(signatureExpiry[game.id].map { AppSignature.isUrgent($0) } == true
                                             ? LauncherPalette.building : .secondary)
                        Button { resign(game) } label: {
                            Text(loc.t("dev.resign")).font(.manrope(12, .semibold))
                                .foregroundStyle(LauncherPalette.cream)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .overlay(Capsule().strokeBorder(LauncherPalette.cream.opacity(0.35)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain).disabled(m.running)
                        .help(loc.t("dev.resignHelp"))
                        .padTarget("hero.resign", scope: "main", radius: 12) { if !m.running { resign(game) } }
                    }
                }
                if let resignNote {
                    Text(resignNote).font(.manrope(12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 34).padding(.bottom, 34)
        }
        .frame(width: width, height: height).clipped()
    }

    func collection(width: CGFloat) -> some View {
        let cardWidth = min(300, max(190, (width - 124) / 5))
        let step = cardWidth + 14
        let games = filteredGames
        let heroID = heroGame?.id
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text(loc.t("library.collection")).font(.manrope(28, .bold)).tracking(-0.6)
                Spacer()
                LauncherSegmented(options: LibraryOrder.choices.map { ($0.rawValue, loc.t($0.labelKey)) },
                                  selection: libraryOrder.rawValue) { setLibraryOrder(LibraryOrder(rawValue: $0) ?? .recent) }
                    .frame(width: LauncherControl.width)
                    // an order arranged by hand (a card dragged here, or RB in console mode) is neither choice: a dot says so
                    .overlay(alignment: .topTrailing) {
                        if libraryOrder == .custom {
                            Circle().fill(LauncherPalette.cream).frame(width: 7, height: 7).offset(x: 2, y: -2).accessibilityHidden(true)
                        }
                    }
                    .help(loc.t(libraryOrder == .custom ? "library.orderCustom" : "order.help"))
                    .padTarget("library.order", scope: "main", radius: 17,
                               activate: { setLibraryOrder(libraryOrder == .recent ? .name : .recent) },
                               adjust: { setLibraryOrder($0 > 0 ? .name : .recent) })
                LauncherSegmented(options: LibraryFilter.allCases.map { ($0.rawValue, loc.t($0.labelKey)) },
                                  selection: libraryFilter.rawValue) { setLibraryFilter(LibraryFilter(rawValue: $0) ?? .owned) }
                    .frame(width: LauncherControl.width)
                    .padTarget("library.filter", scope: "main", radius: 17,
                               activate: { setLibraryFilter(libraryFilter == .owned ? .built : .owned) },
                               adjust: { setLibraryFilter($0 > 0 ? .built : .owned) })
                Text(String(format: loc.t("library.gameCount"), libraryFilter == .owned ? library.games.count : library.games.filter(libraryFilter.includes).count))
                    .font(.manrope(12)).foregroundStyle(.secondary)
            }
            if games.isEmpty {
                Text(loc.t("library.noResults")).foregroundStyle(.secondary).padding(.vertical, 28)
            } else {
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(games) { game in
                                let _ = LauncherWork.count(.card)
                                card(game, width: cardWidth, heroID: heroID, rowWidth: width - 68 + 2 * Self.ringRoom)
                            }
                        }
                        // Room for the controller's focus ring, which sits 4 pt outside a card: the row clips at its edges, so it
                        // gets the room inside and gives it back outside (the cards stay where they were)
                        .padding(.horizontal, Self.ringRoom).padding(.top, Self.ringRoom).padding(.bottom, 5 + Self.ringRoom)
                        .background(EnclosingScrollView(row: row))
                    }
                    .padding(.horizontal, -Self.ringRoom).padding(.vertical, -Self.ringRoom)
                    .coordinateSpace(name: "library.row")
                    .background(GeometryReader { g in Color.clear.preference(key: RowOriginKey.self, value: g.frame(in: .global).minX) })
                    .onPreferenceChange(RowOriginKey.self) { libraryRowOriginX = $0 }
                    .onPreferenceChange(RowFramesKey.self) { frames in cardFrames = frames; libraryDrag.framesChanged(frames); followDrag() }
                    .onAppear {
                        libraryDrag.onEdge = { way in row.scroll(by: CGFloat(way) * step) }   // near an end while dragging: one card that way
                    }
                    .animation(.spring(response: 0.34, dampingFraction: 0.8), value: games.map(\.id))
                    .onChange(of: padFocus.focused) { id in   // the focused card scrolls into the row's view
                        // the AppKit scroll view directly: ScrollViewReader does not scroll a row inside a vertical ScrollView
                        guard let id, id.hasPrefix("card."), let frame = cardFrames[String(id.dropFirst("card.".count))] else { return }
                        row.reveal(minX: frame.minX, maxX: frame.maxX, margin: 24)
                    }
                }
                    .overlay(alignment: .topLeading) {
                        if row.canBack {
                            pager("chevron.left", height: cardWidth / 1.8) { row.page(-1, step: step) }.offset(x: -22)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if row.canForward {
                            pager("chevron.right", height: cardWidth / 1.8) { row.page(1, step: step) }.offset(x: 22)
                        }
                    }
            }
        }
        .padding(.horizontal, 34).padding(.top, 8).padding(.bottom, 22)
    }

    /// One card of the collection. A click selects its game; a long press picks the card up (the order becomes Custom, starting from
    /// the row as it is), it grows a little while pressed, and the mouse then drags it along the row until the button comes up (#937).
    func card(_ game: LibraryGame, width cardWidth: CGFloat, heroID: UUID?, rowWidth: CGFloat) -> some View {
        let id = game.id.uuidString
        let dragged = libraryDrag.id == id
        let lift: CGFloat = dragged ? 1.06 : (libraryDrag.pressing == id ? 1.03 : 1)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image = artwork[game.id] {
                    ArtworkFill(image: image, focus: displayed(game).artwork.focus(for: .thumbnail))
                } else {
                    LauncherPalette.surface
                    Image(systemName: "gamecontroller").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .frame(width: cardWidth, height: cardWidth / 1.8).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(game.id == heroID ? LauncherPalette.cream : .clear, lineWidth: 2))
            Text(game.name).font(.manrope(16, .semibold)).lineLimit(1)
            status(game)
            Capsule().fill(game.id == heroID ? LauncherPalette.cream : .clear).frame(height: 3).padding(.top, 4)
        }
        .frame(width: cardWidth, alignment: .leading).contentShape(Rectangle())
        .rowCardGestures(id: id, drag: libraryDrag, tap: { library.selectedID = game.id }, pick: {
            setLibraryOrder(.custom)
            library.selectedID = game.id
            libraryDrag.begin(id, frame: cardFrames[id], rowOriginX: libraryRowOriginX, rowWidth: rowWidth, onMove: { followDrag() })
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { library.selectedID = game.id }
        .accessibilityAddTraits(game.id == heroID ? .isSelected : [])
        .padTarget("card." + id, scope: "main", radius: 7) { if !launching { primaryAction(game) } }
        .scaleEffect(lift)
        .shadow(color: .black.opacity(dragged ? 0.5 : (libraryDrag.pressing == id ? 0.3 : 0)), radius: 16, y: 10)
        .animation(.easeOut(duration: 0.25), value: lift)
        .offset(x: libraryDrag.offset(for: id))
        .zIndex(dragged ? 1 : 0)
        .transaction { if dragged { $0.animation = nil } }   // under the pointer at once; the others spring aside
        .background(GeometryReader { g in
            Color.clear.preference(key: RowFramesKey.self, value: [id: g.frame(in: .named("library.row"))])
        })
    }

    /// The dragged card takes one step toward the pointer once it has passed the next card; the library keeps it at once, and the
    /// card takes its new place at once too, so it does not jump while the frames come back.
    func followDrag() {
        guard libraryDrag.active, let dragID = libraryDrag.id, let id = UUID(uuidString: dragID) else { return }
        let shown = filteredGames.map(\.id)
        let order = shown.map(\.uuidString)
        let step = libraryDrag.step(order: order, frames: cardFrames)
        guard step != 0, let at = order.firstIndex(of: dragID), order.indices.contains(at + step) else { return }
        libraryDrag.stepped(into: cardFrames[order[at + step]], step: step, frame: cardFrames[dragID])
        guard library.move(id, by: step, among: shown) else { libraryDrag.framesChanged(cardFrames); return }
        RowDrag.haptic(.alignment)
    }

    /// A round button floating over the row's edge, centred on the artwork, shown while the row scrolls that way.
    func pager(_ symbol: String, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.72), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16)))
                .shadow(color: .black.opacity(0.4), radius: 10)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .accessibilityLabel(loc.t(symbol == "chevron.left" ? "library.scrollBack" : "library.scrollForward"))
        .transition(.opacity)
    }

    func status(_ game: LibraryGame, prominent: Bool = false) -> some View {
        let building = m.running && activeBuildID == game.id
        let color = building ? LauncherPalette.building : ((game.isReady || game.hasIOSBuild) ? LauncherPalette.ready : LauncherPalette.unbuilt)
        let key = building ? "library.building" : (game.isReady ? "library.ready" : (game.hasIOSBuild ? (game.isOlderIOSBuild ? "library.olderIOS" : "library.readyIOS") : "library.notBuilt"))
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: prominent ? 9 : 7, height: prominent ? 9 : 7)
            Text(prominent ? loc.t(key).uppercased() : loc.t(key))
                .font(prominent ? .manrope(12, .bold) : .manrope(13, .medium))
                .tracking(prominent ? 1.3 : 0)   // the eyebrow: the same face, in tracked capitals
                .foregroundStyle(color)
            if GameFolder.profileIsSwitch2(game.titleID, engineRoot: EngineLayout.root(m.repo.path)) {   // #445
                Text(loc.t("switch2.badge"))
                    .font(.manrope(prominent ? 11 : 10.5, .bold)).foregroundStyle(LauncherPalette.cream.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(LauncherPalette.cream.opacity(0.35)))
                    .help(loc.t("switch2.help"))
            }
            if !building && toolsAge.older.contains(game.id) {   // a quiet note beside the status, not a warning
                Text("· " + loc.t(prominent ? "library.olderTools" : "library.olderToolsShort"))
                    .font(.manrope(prominent ? 13 : 12)).foregroundStyle(.secondary).lineLimit(1)
                    .help(loc.t("library.olderToolsHelp"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
