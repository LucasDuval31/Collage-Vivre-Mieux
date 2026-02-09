struct StatsView: some View {
    @EnvironmentObject var vm: PanelsVM
    @Environment(\.modelContext) private var modelContext
    @State private var searchAssignee: String = ""

    var body: some View {
        NavigationStack {
            List {
                // --- SECTION 1 : RÉSUMÉ (CHIPS STATS) ---
                Section("Vue d'ensemble") {
                    HStack(spacing: 20) {
                        statChip(title: "Assignés", count: vm.allLocalStatuses.filter({$0.assignedTo != nil}).count, color: .blue)
                        statChip(title: "Restants", count: vm.allPanels.count - vm.allLocalStatuses.filter({$0.assignedTo != nil}).count, color: .orange)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                // --- SECTION 2 : BACK-OFFICE (RÉPARTITION) ---
                Section {
                    let assignees = vm.panelsByAssignee.keys.sorted()
                    
                    ForEach(assignees, id: \.self) { name in
                        DisclosureGroup {
                            let panels = vm.panelsByAssignee[name] ?? []
                            ForEach(panels) { panel in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(panel.title)
                                            .font(.subheadline)
                                        Text(panel.subtitle)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    // Petit indicateur d'état (collé ou non)
                                    statusIndicator(for: panel.id)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        vm.toggleResponsibility(panelId: panel.id, userName: name, modelContext: modelContext)
                                    } label: {
                                        Label("Retirer", systemImage: "person.fill.xmark")
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(name)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(vm.panelsByAssignee[name]?.count ?? 0) panneaux")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } header: {
                    Text("Répartition par référent")
                }
            }
            .navigationTitle("Back-Office")
            .searchable(text: $searchAssignee, prompt: "Chercher un référent")
        }
    }

    // Helpers de vue
    func statChip(title: String, count: Int, color: Color) -> some View {
        VStack {
            Text("\(count)").font(.title2).bold().foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    func statusIndicator(for id: String) -> some View {
        let s = vm.status(forPanelId: id)
        return Circle()
            .fill(s.lastCoveredAt != nil ? .green : (s.isAbsent ? .red : .gray.opacity(0.3)))
            .frame(width: 8, height: 8)
    }
}