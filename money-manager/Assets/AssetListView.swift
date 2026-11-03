import SwiftUI
import SwiftData
import MoneyCore

/// What the asset sheet opens with.
enum AssetFormRoute: Identifiable {
    case create
    case edit(AssetAccount)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let asset): asset.id.uuidString
        }
    }
}

/// "Aset" tab: net worth summary and the assets grouped by type.
struct AssetListView: View {
    @Environment(ProfileStore.self) private var store
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var showsArchived = false
    @State private var formRoute: AssetFormRoute?

    private var activeProfile: Profile? {
        profiles.first { $0.id == store.activeProfileID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = activeProfile {
                    ProfileAssetsView(
                        profile: profile,
                        showsArchived: showsArchived,
                        onOpen: { formRoute = $0 }
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Aset")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Tampilkan arsip", systemImage: "archivebox", isOn: $showsArchived)
                        .toggleStyle(.button)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tambah aset", systemImage: "plus") { formRoute = .create }
                        .accessibilityLabel("Tambah aset")
                        .disabled(activeProfile == nil)
                }
            }
            .sheet(item: $formRoute) { route in
                switch route {
                case .create: AssetFormView(mode: .create)
                case .edit(let asset): AssetFormView(mode: .edit(asset))
                }
            }
        }
    }
}

/// Owns the `@Query`s for one profile; rebuilt when the active profile changes.
private struct ProfileAssetsView: View {
    let profile: Profile
    let showsArchived: Bool
    let onOpen: (AssetFormRoute) -> Void

    @Environment(\.modelContext) private var context
    @Query private var assets: [AssetAccount]
    @Query private var transactions: [MoneyTransaction]

    init(profile: Profile, showsArchived: Bool, onOpen: @escaping (AssetFormRoute) -> Void) {
        self.profile = profile
        self.showsArchived = showsArchived
        self.onOpen = onOpen
        let profileID = profile.id
        _assets = Query(FetchDescriptor<AssetAccount>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        ))
        _transactions = Query(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == profileID }))
    }

    private var visibleAssets: [AssetAccount] {
        showsArchived ? assets : assets.filter { !$0.isArchived }
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    @ViewBuilder
    private var content: some View {
        if visibleAssets.isEmpty {
            emptyState
        } else {
            List {
                ForEach(AssetGroup.allCases, id: \.self) { group in
                    let inGroup = visibleAssets.filter { $0.group == group }
                    if !inGroup.isEmpty {
                        Section {
                            ForEach(inGroup) { asset in
                                row(for: asset)
                            }
                        } header: {
                            GroupHeader(group: group, subtotal: subtotal(of: inGroup))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if assets.isEmpty {
            ContentUnavailableView {
                Label("Belum ada aset", systemImage: "building.columns")
            } description: {
                Text("Tambahkan dompet, rekening, atau kartu untuk melacak saldo.")
            } actions: {
                Button("Tambah aset") { onOpen(.create) }
                    .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView(
                "Semua aset diarsipkan",
                systemImage: "archivebox",
                description: Text("Nyalakan \"Tampilkan arsip\" untuk melihatnya.")
            )
        }
    }

    private func row(for asset: AssetAccount) -> some View {
        NavigationLink {
            AssetDetailView(asset: asset)
        } label: {
            AssetRow(asset: asset, balance: BalanceCalculator.balance(of: asset, transactions: transactions))
        }
        .swipeActions(edge: .trailing) {
            if asset.isArchived {
                Button("Aktifkan", systemImage: "tray.and.arrow.up") { setArchived(asset, false) }
                    .tint(.indigo)
            } else {
                Button("Arsipkan", systemImage: "archivebox") { setArchived(asset, true) }
                    .tint(.indigo)
            }
        }
        .swipeActions(edge: .leading) {
            Button("Ubah", systemImage: "pencil") { onOpen(.edit(asset)) }
                .tint(.orange)
        }
    }

    private func subtotal(of group: [AssetAccount]) -> Decimal {
        group.reduce(0) { $0 + BalanceCalculator.balance(of: $1, transactions: transactions) }
    }

    // MARK: Header

    private var header: some View {
        // Archived assets still count: their money is still there.
        let netWorth = BalanceCalculator.netWorth(assets: assets, transactions: transactions)
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color(hex: profile.colorHex))
                    .frame(width: 4, height: 18)
                    .accessibilityHidden(true)
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .top) {
                SummaryColumn(title: "Aset", amount: netWorth.assets, color: .blue)
                SummaryColumn(title: "Liabilitas", amount: netWorth.liabilities, color: .red)
                SummaryColumn(title: "Total", amount: netWorth.total, color: .primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        // Pinned bar: capped like system bars so accessibility sizes don't fill the screen; the list still scales.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Opaque so rows scroll beneath it; `.safeAreaBar` blurred the large title.
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: [])
    }

    // MARK: Actions

    private func setArchived(_ asset: AssetAccount, _ archived: Bool) {
        do {
            try AssetService(context: context, profileID: profile.id).setArchived(asset, archived)
        } catch {
            assertionFailure("Arsip aset gagal: \(error)")
        }
    }
}

private struct GroupHeader: View {
    let group: AssetGroup
    let subtotal: Decimal

    var body: some View {
        HStack {
            Text(group.displayName)
            Spacer()
            Text(MoneyFormatter.string(subtotal))
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.displayName), subtotal \(MoneyFormatter.string(subtotal))")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct AssetRow: View {
    let asset: AssetAccount
    let balance: Decimal

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked so nothing truncates at accessibility sizes.
                VStack(alignment: .leading, spacing: 4) {
                    nameAndNotes
                    balanceText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    nameAndNotes
                    Spacer(minLength: 8)
                    balanceText
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var nameAndNotes: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.name)
                .font(.body)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            if let notes {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var balanceText: some View {
        Text(MoneyFormatter.string(balance))
            .font(.body.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(balance < 0 ? .red : .primary)
    }

    private var notes: String? {
        let parts = [asset.isArchived ? "Diarsipkan" : nil, asset.includeInTotal ? nil : "Tidak masuk total"]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct SummaryColumn: View {
    let title: String
    let amount: Decimal
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.string(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
