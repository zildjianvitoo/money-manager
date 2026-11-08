import SwiftUI
import SwiftData
import MoneyCore

/// Exports a profile's transactions to CSV and hands the file to the share sheet.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProfileStore.self) private var store
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var profileID: UUID?
    @State private var limitRange = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    @State private var fileURL: URL?
    @State private var count = 0
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Profil") {
                Picker("Profil", selection: $profileID) {
                    ForEach(profiles) { Text("\($0.emoji) \($0.name)").tag(Optional($0.id)) }
                }
            }
            Section {
                Toggle("Batasi tanggal", isOn: $limitRange)
                if limitRange {
                    DatePicker("Dari", selection: $from, displayedComponents: .date)
                    DatePicker("Sampai", selection: $to, displayedComponents: .date)
                }
            } footer: {
                Text("Format CSV (UTF-8) dengan kolom yang sama seperti saat import, jadi bisa diimpor lagi. Penyesuaian saldo tidak ikut diekspor.")
            }
            Section {
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("Bagikan \(count) transaksi", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text(errorMessage ?? "Tidak ada transaksi untuk diekspor.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profileID = profileID ?? store.activeProfileID }
        .onChange(of: profileID) { prepare() }
        .onChange(of: limitRange) { prepare() }
        .onChange(of: from) { prepare() }
        .onChange(of: to) { prepare() }
        .task { prepare() }
    }

    private func prepare() {
        fileURL = nil
        errorMessage = nil
        guard let pid = profileID, let profile = profiles.first(where: { $0.id == pid }) else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(from, to))
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, to))) ?? .distantFuture
        do {
            var transactions = try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == pid }))
            if limitRange { transactions = transactions.filter { $0.date >= start && $0.date < end } }
            transactions = transactions.filter { $0.type != .adjustment }
            count = transactions.count
            guard !transactions.isEmpty else { return }

            let stamp = Date.now.formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Duitku-\(profile.name)-\(stamp).csv".replacingOccurrences(of: "/", with: "-"))
            try CSVTransactions.export(transactions).write(to: url, options: .atomic)
            fileURL = url
        } catch {
            errorMessage = "Gagal menyiapkan file: \(error.localizedDescription)"
        }
    }
}
