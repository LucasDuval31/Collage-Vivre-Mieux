import SwiftUI
import MapKit
import SwiftData
import CoreLocation

struct ContentView: View {

    // MARK: - VM + Data
    @StateObject private var vm = PanelsVM()
    @StateObject private var loc = LocationManager()

    @Environment(\.modelContext) private var modelContext
    @Query private var statuses: [PanelLocalStatus]

    @AppStorage("campaign_user_name") private var userName: String = "Équipe"

    @AppStorage("map_mode") private var mapModeRaw: String = MapMode.free.rawValue
    private var mapMode: MapMode { MapMode(rawValue: mapModeRaw) ?? .free }

    @State private var filter: PanelFilter = .todo
    @State private var search: String = ""

    // sélection unifiée (OpenData + Extra + Voting sites)
    @State private var selectedItem: PanelItem?

    // Menu sheets
    @State private var showNearby = false
    @State private var showActivity = false
    @State private var showDashboard = false
    @State private var showAlerts = false

    // Ajout extra panneau (Option B)
    @State private var showAddExtraSheet = false
    @State private var addExtraLocation: CLLocation?
    @State private var addExtraError: String?

    // Map
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.6047, longitude: 1.4442),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )
    @State private var didCenterOnUser = false

    // Bottom drawer
    @State private var drawerHeight: CGFloat = 190

    // MARK: - Drawer helpers
    private let drawerMinHeight: CGFloat = 120

    private func collapseDrawer() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            drawerHeight = drawerMinHeight
        }
    }

    var body: some View {
        NavigationStack {

            GeometryReader { geo in
                ZStack(alignment: .bottom) {

                    // MARK: - Map
                    MapReader { proxy in
                        Map(position: $position) {

                            UserAnnotation()

                            switch mapMode {
                            case .free:
                                // OpenData panels
                                ForEach(filteredPanels) { panel in
                                    if let item = panel.asPanelItem {
                                        Annotation(item.title, coordinate: item.coordinate) {
                                            ZStack {
                                                Color.clear.frame(width: 44, height: 44)
                                                PanelPin(status: status(forPanelId: item.id))
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                collapseDrawer()
                                                selectedItem = item
                                            }
                                        }
                                    }
                                }

                                // Extra panels
                                ForEach(vm.extraPanels) { ep in
                                    let item = ep.asPanelItem
                                    Annotation(item.title, coordinate: item.coordinate) {
                                        ZStack {
                                            Color.clear.frame(width: 44, height: 44)
                                            ExtraPanelPin(status: status(forPanelId: item.id))
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            collapseDrawer()
                                            selectedItem = item
                                        }
                                    }
                                }

                            case .vote:
                                // ✅ 1 pin par "lieu de vote"
                                ForEach(vm.votingSites) { site in
                                    Annotation(site.title, coordinate: site.coordinate) {
                                        ZStack {
                                            Color.clear.frame(width: 44, height: 44)
                                            PanelPin(status: status(forPanelId: site.id))
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            collapseDrawer()
                                            selectedItem = PanelItem(
                                                id: site.id,
                                                title: site.title,
                                                subtitle: site.subtitle,
                                                coordinate: site.coordinate,
                                                isExtra: false
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .mapControls {
                            MapCompass()
                            MapScaleView()
                        }
                        // ✅ Tap simple sur la map => ferme la liste
                        .onTapGesture {
                            collapseDrawer()
                        }
                        // ✅ Correction syntaxe iOS 17+
                        .onChange(of: loc.location) { oldValue, newValue in
                            guard let l = newValue, didCenterOnUser == false else { return }
                            didCenterOnUser = true
                            position = .region(
                                MKCoordinateRegion(
                                    center: l.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                )
                            )
                        }
                        .ignoresSafeArea()
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                guard let l = loc.location else { return }
                                position = .region(
                                    MKCoordinateRegion(
                                        center: l.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                    )
                                )
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.headline)
                                    .padding(12)
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                                    .shadow(radius: 6)
                            }
                            .disabled(loc.location == nil)
                            .padding(.trailing, 16)
                            .padding(.bottom, drawerHeight + 16)
                        }
                        // ✅ GESTE SPATIAL : Capture de la position lors de l'appui long
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 1.0)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global)) // 1. On utilise le référentiel global
                                .onEnded { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if let location = drag?.location {
                                            // 2. On convertit depuis le référentiel global vers la carte
                                            guard mapMode == .free,
                                                  let coord = proxy.convert(location, from: .global)
                                            else { return }

                                            // 3. Retour haptique pour confirmer l'appui précis
                                            let generator = UIImpactFeedbackGenerator(style: .medium)
                                            generator.impactOccurred()

                                            collapseDrawer()
                                            addExtraLocation = CLLocation(
                                                latitude: coord.latitude,
                                                longitude: coord.longitude
                                            )
                                            showAddExtraSheet = true
                                        }
                                    default: break
                                    }
                                }
                        )
                    }

                    // MARK: - Bottom Drawer
                    BottomDrawer(
                        height: $drawerHeight,
                        minHeight: drawerMinHeight,
                        maxHeight: min(geo.size.height * 0.78, 620)
                    ) {
                        listContent
                    }
                }
            }

            // MARK: - Initial load + sync + location
            .task {
                loc.request()
                await vm.loadPanels()
                await vm.loadExtraPanels()
                await vm.loadVotingSites()
                await vm.syncFromServer(modelContext: modelContext)
            }

            // ✅ UI du haut : Top bar puis Progress (collé au safe area)
            .safeAreaInset(edge: .top, spacing: 0) {
                let lift: CGFloat = -60 // 👈 remonte vers la Dynamic Island (ajuste si besoin)

                VStack(spacing: 8) {
                    topBar

                    // Progress juste en dessous
                    VStack(spacing: 6) {
                        CoverageBar(progress: coverageProgress)
                        Text(progressText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 10)
                .offset(y: lift)
                .background(Color.clear)
            }

            // MARK: - Panel detail
                        .sheet(item: $selectedItem) { item in
                            PanelDetailSheet(
                                panel: item,
                                status: status(forPanelId: item.id),
                                userName: userName,
                                onCovered: { coveredAt, note, photoFilename in
                                    Task {
                                        await vm.markCovered(
                                            panelId: item.id,
                                            coveredAt: coveredAt,
                                            coveredBy: userName,
                                            note: note,
                                            photoFilename: photoFilename,
                                            modelContext: modelContext
                                        )
                                    }
                                },
                                onOverposted: { at, note in
                                    Task {
                                        await vm.markOverposted(
                                            panelId: item.id,
                                            at: at,
                                            by: userName,
                                            note: note,
                                            modelContext: modelContext
                                        )
                                    }
                                },
                                onMarkTodo: { at in
                                    Task {
                                        await vm.markTodo(
                                            panelId: item.id,
                                            at: at,
                                            by: userName,
                                            modelContext: modelContext
                                        )
                                    }
                                },
                                onReportAbsent: { reason in
                                    Task {
                                        await vm.reportAbsent(
                                            panelId: item.id,
                                            reportedAt: Date(),
                                            reportedBy: userName,
                                            reason: reason,
                                            modelContext: modelContext
                                        )
                                    }
                                }
                            )
                            .environmentObject(vm) // ✅ Injection indispensable du VM ici
                        }
            // MARK: - Add Extra Panel sheet (Option B)
            .sheet(isPresented: $showAddExtraSheet) {
                if let l = addExtraLocation {
                    NavigationStack {
                        AddExtraPanelSheet(location: l, userName: userName) { title, subtitle in
                            Task {
                                await vm.addExtraPanel(
                                    lat: l.coordinate.latitude,
                                    lon: l.coordinate.longitude,
                                    title: title,
                                    subtitle: subtitle,
                                    createdBy: userName
                                )
                            }
                        }
                    }
                }
            }

            // MARK: - Nearby (mode free seulement)
            .sheet(isPresented: $showNearby) {
                NavigationStack {
                    TourView(
                        panels: vm.panels,
                        statusFor: { status(for: $0) },
                        currentLocation: loc.location
                    )
                }
            }

            // MARK: - Activity
            .sheet(isPresented: $showActivity) {
                NavigationStack {
                    ActivityView(events: vm.recentEvents)
                        .task { await vm.loadRecentActivity() }
                }
            }

            // MARK: - Dashboard
            .sheet(isPresented: $showDashboard) {
                NavigationStack {
                    DashboardView(
                        totalPanels: activePanelIds.count,
                        events: vm.dashboardEvents,
                        absentNowCount: absentNowCount,
                        absentAllTimeCount: absentAllTimeCount
                    )
                    .task { await vm.loadDashboardData() }
                }
            }

            // MARK: - Alerts
            .sheet(isPresented: $showAlerts) {
                NavigationStack {
                    AlertsView(
                        panels: vm.panels,
                        statusFor: { status(for: $0) }
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Top Bar
    private var topBar: some View {
        VStack(spacing: 10) {

            Picker("", selection: $mapModeRaw) {
                ForEach(MapMode.allCases) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                TextField("Ton prénom", text: $userName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        await vm.loadPanels()
                        await vm.loadExtraPanels()
                        await vm.loadVotingSites()
                        await vm.syncFromServer(modelContext: modelContext)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button {
                        loc.request()
                        showNearby = true
                    } label: {
                        Label("Panneaux proches", systemImage: "location.north.line")
                    }
                    .disabled(mapMode == .vote)

                    Button { showActivity = true } label: {
                        Label("Activité récente", systemImage: "list.bullet.rectangle")
                    }

                    Button { showDashboard = true } label: {
                        Label("Tableau de bord", systemImage: "chart.bar")
                    }

                    Button { showAlerts = true } label: {
                        Label("Alertes", systemImage: "exclamationmark.triangle")
                    }

                    Divider()

                    Button {
                        guard let l = loc.location else { return }
                        addExtraLocation = l
                        showAddExtraSheet = true
                    } label: {
                        Label("Ajouter un panneau ici", systemImage: "plus")
                    }
                    .disabled(loc.location == nil || mapMode == .vote)

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.bordered)
            }

            // ✅ Filtre TOUJOURS visible
            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(PanelFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)

                // 🔎 Recherche uniquement en mode "free"
                if mapMode == .free {
                    TextField("Rechercher…", text: $search)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if vm.isLoading { ProgressView() }

            if let e = vm.error {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let e = addExtraError {
                Text("Ajout panneau: \(e)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Drawer List
    private var listContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mapMode == .free ? "Panneaux" : "Lieux de vote")
                    .font(.headline)
                Spacer()
                Text("\(activePanelIds.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 6)

            Divider().padding(.top, 6)

            if mapMode == .free {
                List(filteredPanels) { panel in
                    Button {
                        if let item = panel.asPanelItem {
                            collapseDrawer()
                            selectedItem = item
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            PanelDot(status: status(for: panel))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(panel.title).font(.headline)
                                if !panel.subtitle.isEmpty {
                                    Text(panel.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text(line(for: panel))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)

            } else {

                List(dedupedVotingSites, id: \.id) { site in
                    Button {
                        collapseDrawer()
                        selectedItem = PanelItem(
                            id: site.id,
                            title: site.title,
                            subtitle: votingSubtitle(for: site),
                            coordinate: site.coordinate,
                            isExtra: false
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            PanelDot(status: status(forPanelId: site.id))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.title).font(.headline)

                                let sub = votingSubtitle(for: site)
                                if !sub.isEmpty {
                                    Text(sub)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Text(lineForPanelId(site.id))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func status(forPanelId panelId: String) -> PanelComputedStatus {
        let local = statuses.first { $0.panelId == panelId }
        return PanelComputedStatus(local: local)
    }

    private func status(for panel: OpenDataPanel) -> PanelComputedStatus {
        let local = statuses.first { $0.panelId == panel.id }
        return PanelComputedStatus(local: local)
    }

    private var filteredPanels: [OpenDataPanel] {
        vm.panels
            .filter { panel in
                let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return true }
                return panel.title.localizedCaseInsensitiveContains(q)
                || panel.subtitle.localizedCaseInsensitiveContains(q)
            }
            .filter { panel in
                let s = status(for: panel)
                switch filter {
                case .all: return true
                case .todo: return s.bucket == .todo
                case .upToDate: return s.bucket == .upToDate
                case .old: return s.bucket == .old
                case .absent: return s.bucket == .absent
                case .pending: return s.bucket == .pendingSync
                }
            }
    }

    private func line(for panel: OpenDataPanel) -> String {
        lineForPanelId(panel.id)
    }

    private func lineForPanelId(_ panelId: String) -> String {
        let s = status(forPanelId: panelId)
        switch s.bucket {
        case .absent:
            let who = s.local?.absentBy ?? "—"
            let reason = (s.local?.absentReason?.isEmpty == false) ? " • \(s.local!.absentReason!)" : ""
            return "Absent • \(s.whenText) • \(who)\(reason)"

        case .todo:
            return "À faire"

        case .upToDate:
            let who = s.local?.lastCoveredBy ?? "—"
            return "À jour (<24h) • \(s.whenText) • \(who)"

        case .old:
            let who = s.local?.lastCoveredBy ?? "—"
            return "À refaire • \(s.whenText) • \(who)"

        case .pendingSync:
            return "En attente de sync"

        case .overposted:
            let who = s.local?.overpostedBy ?? "—"
            let note = (s.local?.overpostedNote?.isEmpty == false) ? " • \(s.local!.overpostedNote!)" : ""
            return "Adversaires • \(s.whenText) • \(who)\(note)"
        }
    }

    // MARK: - Voting helpers

    private func votingSubtitle(for site: VotingSite) -> String {
        let base = site.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let bureaux = site.bureauList
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        if bureaux.isEmpty { return base }

        let bureauxText = "Bureaux \(bureaux.joined(separator: ", "))"
        if base.localizedCaseInsensitiveContains("Bureaux") { return base }
        if base.isEmpty { return bureauxText }
        return base + " • " + bureauxText
    }

    private var dedupedVotingSites: [VotingSite] {
        var seen = Set<String>()
        var out: [VotingSite] = []
        for s in vm.votingSites {
            let key = (s.title + "|" + s.subtitle).lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(s)
        }
        return out
    }

    // MARK: - Progress / Stats (mode dépendant)

    private var activePanelIds: [String] {
        switch mapMode {
        case .free:
            let openIds = vm.panels.map { $0.id }
            let extraIds = vm.extraPanels.map { $0.asPanelItem.id }
            return openIds + extraIds
        case .vote:
            return dedupedVotingSites.map { $0.id }
        }
    }

    private var absentNowCount: Int {
        var count = 0
        for id in activePanelIds {
            if let s = statuses.first(where: { $0.panelId == id }),
               s.isAbsent == true {
                count += 1
            }
        }
        return count
    }

    private var absentAllTimeCount: Int {
        var set = Set<String>()
        for ev in vm.dashboardEvents {
            if (ev.event_type ?? "covered").lowercased() == "absent" {
                set.insert(ev.panel_id)
            }
        }
        return set.count
    }

    private var upToDateCount: Int {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        var count = 0
        for id in activePanelIds {
            guard let s = statuses.first(where: { $0.panelId == id }) else { continue }
            if s.isAbsent { continue }
            if s.isOverposted { continue }
            if let d = s.lastCoveredAt, d >= cutoff { count += 1 }
        }
        return count
    }

    private var effectiveTotal: Int {
        max(activePanelIds.count - absentNowCount, 1)
    }

    private var coverageProgress: Double {
        Double(upToDateCount) / Double(effectiveTotal)
    }

    private var progressText: String {
        "\(Int(coverageProgress * 100))% à jour (<24h) • \(upToDateCount)/\(effectiveTotal) — Absents: \(absentNowCount)"
    }
}

// MARK: - BottomDrawer
private struct BottomDrawer<Content: View>: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let content: Content

    @GestureState private var dragDelta: CGFloat = 0

    init(
        height: Binding<CGFloat>,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self._height = height
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .frame(width: 44, height: 6)
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.top, 8)
                .padding(.bottom, 8)

            content
        }
        .frame(height: clampedHeight)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($dragDelta) { value, state, _ in
                    state = -value.translation.height
                }
                .onEnded { value in
                    let proposed = height + (-value.translation.height)
                    let mid = (minHeight + maxHeight) / 2
                    let snapped: CGFloat
                    if proposed < mid * 0.85 { snapped = minHeight }
                    else if proposed > mid * 1.15 { snapped = maxHeight }
                    else { snapped = mid }
                    height = snapped
                }
        )
        .onAppear {
            height = max(minHeight, min(height, maxHeight))
        }
    }

    private var clampedHeight: CGFloat {
        let proposed = height + dragDelta
        return min(max(proposed, minHeight), maxHeight)
    }
}
