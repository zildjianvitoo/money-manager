import SwiftUI
import SwiftData
import MoneyCore

/// Import batches of the active profile, each of which can be undone.
struct ImportHistoryView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        Group {
            if let profileID = store.activeProfileID {
                BatchList(profileID: profileID).id(profileID)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Riwayat Import")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PendingUndo {
    let id: UUID
    let fileName: String
    let rowCount: Int
}

private struct BatchList: View {
    let profileID: UUID
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Query private var batches: [ImportBatch]
    @State private var pending: PendingUndo?
    @State private var errorMessage: String?

    init(profileID: UUID) {
        self.profileID = profileID
        _batches = Query(filter: #Predicate<ImportBatch> { $0.profileID == profileID },
                         sort: [SortDescriptor(\.importedAt, order: .reverse)])
    }

    var body: some View {
        List {
            if batches.isEmpty {
                ContentUnavailableView("Belum ada import", systemImage: "tray", description: Text("Hasil import muncul di sini dan bisa dibatalkan."))
            }
            ForEach(batches) { batch in
                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.fileName).font(.headline).lineLimit(1)
                    Text("\(batch.rowCount) transaksi · \(batch.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if batch.skippedCount > 0 {
                        Text("\(batch.skippedCount) dilewati (sudah ada)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Batalkan", role: .destructive) {
                        pending = PendingUndo(id: batch.id, fileName: batch.fileName, rowCount: batch.rowCount)
                    }
                }
            }
        }
        .alert("Batalkan import?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { item in
            Button("Kembali", role: .cancel) {}
            Button("Batalkan import", role: .destructive) { undo(item) }
        } message: { item in
            Text("\(item.rowCount) transaksi dari \(item.fileName) dihapus. Kategori dan aset yang dibuat import ini ikut dihapus bila tidak dipakai lagi. Tidak bisa dikembalikan.")
        }
        .alert("Gagal membatalkan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func undo(_ item: PendingUndo) {
        guard let batch = batches.first(where: { $0.id == item.id }) else { return }
        do {
            try ImportService(context: context, profileID: profileID).undo(batch)
            toastCenter.show("Import dibatalkan")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
