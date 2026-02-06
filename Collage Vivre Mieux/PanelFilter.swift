import SwiftUI
import MapKit
import SwiftData
import CoreLocation

enum PanelFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case todo = "À faire"
    case upToDate = "À jour (<24h)"
    case old = "À refaire"
    case absent = "Absents"
    case pending = "À sync"
    var id: String { rawValue }
}

// ✅ V2 : mode carte exclusif
enum MapMode: String, CaseIterable, Identifiable {
    case free = "Expression libre"
    case vote = "Panneaux électoraux"
    var id: String { rawValue }
}

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

    // ✅ sélection unifiée (OpenData + Extra + Voting sites)
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

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .top) {

                    // MARK: - Map
                    Map(position: $position) {

                        UserAnnotation()

                        switch mapMode {
                        case .free:
                            // OpenData panels
                            ForEach(filteredPanels) { panel in
                                if let item = panel.asPanelItem {
                                    Annotation(item.title, coordinate: item.coordinate) {
                                        PanelPin(status: status(forPanelId: item.id))
                                            .onTapGesture { selectedItem = item }
                                    }
                                }
                            }

                            // Extra panels
                            ForEach(vm.extraPanels) { ep in
                                let item = ep.asPanelItem
                                Annotation(item.title, coordinate: item.coordinate) {
                                    ExtraPanelPin(status: status(forPanelId: item.id))
                                        .onTapGesture { selectedItem = item }
                                }
                            }

                        case .vote:
                            // 1 pin par lieu (VotingSite.id = "vote:...") -> status OK
                            ForEach(vm.votingSites) { site in
                                Annotation(site.title, coordinate: site.coordinate) {
                                    PanelPin(status: status(forPanelId: site.id))
                                        .onTapGesture {
                                            selectedItem = PanelItem(
                                                id: site.id,
                                                title: site.title,
                                                subtitle: site.subtitle,
                                                coordinate: site.coordinate
                                            )
                                        }
                                }
                            }
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    // ⚠️ version sûre (build ok même si target < iOS 17) : warning only
                    .onChange(of: loc.location) { newValue in
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
                    .overlay(alignment: Alignment.top) {
                        VStack(spacing: 8) {
                            VStack(spacing: 6) {
                                CoverageBar(progress: coverageProgress)
                                Text(progressText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                            topBar
                        }
                    }

                    // MARK: - Bottom Drawer
                    BottomDrawer(
                        height: $drawerHeight,
                        minHeight: 120,
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

            // MARK: - Nearby (Panneaux proches) (mode free seulement)
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
                        totalPanels: activePanelIds.count, // ✅ dépend du mode
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
    }

    // MARK: - Top Bar
    private var topBar: some View {
        VStack(spacing: 10) {

            // ✅ V2 switch exclusif
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

            if mapMode == .free {
                HStack(spacing: 10) {
                    Picker("", selection: $filter) {
                        ForEach(PanelFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Rechercher…", text: $search)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if vm.isLoading {
                ProgressView()
            }
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
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 4)
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

            // Pour l’instant: liste basée sur OpenData (free) / sites (vote)
            if mapMode == .free {
                List(filteredPanels) { panel in
                    Button {
                        if let item = panel.asPanelItem { selectedItem = item }
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
                List(vm.votingSites, id: \.id) { site in
                    Button {
                        selectedItem = PanelItem(
                            id: site.id,
                            title: site.title,
                            subtitle: site.subtitle,
                            coordinate: site.coordinate
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            PanelDot(status: status(forPanelId: site.id))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.title).font(.headline)
                                if !site.subtitle.isEmpty {
                                    Text(site.subtitle)
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
        }
    }

    // MARK: - Progress / Stats (✅ dépend du mode)

    private var activePanelIds: [String] {
        switch mapMode {
        case .free:
            let openIds = vm.panels.map { $0.id }
            let extraIds = vm.extraPanels.map { $0.asPanelItem.id }
            return openIds + extraIds
        case .vote:
            return vm.votingSites.map { $0.id } // "vote:..."
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

    private var upToDateCount: Int {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        var count = 0
        for id in activePanelIds {
            guard let s = statuses.first(where: { $0.panelId == id }) else { continue }
            if s.isAbsent { continue }
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

    private var absentAllTimeCount: Int {
        var set = Set<String>()
        for ev in vm.dashboardEvents {
            if (ev.event_type ?? "covered").lowercased() == "absent" {
                set.insert(ev.panel_id)
            }
        }
        return set.count
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