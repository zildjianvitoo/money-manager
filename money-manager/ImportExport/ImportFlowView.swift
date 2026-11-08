import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MoneyCore

/// Import wizard in one screen: pick a file, choose the target profile, review the preview, import.
struct ImportFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var isPicking = false
    @State private var isReading = false
    @State private var fileName: String?
    @State private var parsed: ImportParseResult?
    @State private var targetID: UUID?
    @State private var preview: ImportPreview?
    @State private var skipDuplicates = true
    @State private var outcome: ImportOutcome?
    @State private var errorMessage: String?

    private var service: ImportService? {
        targetID.map { ImportService(context: context, profileID: $0) }
    }

    var body: some View {
        List {
            fileSection
            if let parsed, let preview {
                profileSection
                summarySection(preview)
                if !preview.months.isEmpty { monthsSection(preview) }
                if !preview.newCategoryNames.isEmpty || !preview.newAssetNames.isEmpty { newItemsSection(preview) }
                if !parsed.failures.isEmpty { failuresSection(parsed.failures) }
                if let outcome { resultSection(outcome) } else { importSection(preview) }
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Import gagal", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { targetID = targetID ?? store.activeProfileID }
        .onChange(of: targetID) { refreshPreview() }
    }

    // MARK: Sections

    private var fileSection: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                HStack {
                    Label(fileName ?? "Pilih file…", systemImage: "doc.badge.plus")
                    Spacer()
                    if isReading { ProgressView() }
                }
            }
            .disabled(isReading)
        } footer: {
            Text("Mendukung backup JSON dari Money Manager dan file CSV (kolom Date, Account, Category, Subcategory, Note, Amount, Type).")
        }
    }

    private var profileSection: some View {
        Section("Profil tujuan") {
            Picker("Profil", selection: $targetID) {
                ForEach(profiles) { profile in
                    Text("\(profile.emoji) \(profile.name)").tag(Optional(profile.id))
                }
            }
            .disabled(outcome != nil)
        }
    }

    private func summarySection(_ preview: ImportPreview) -> some View {
        Section("Pratinjau") {
            LabeledContent("Transaksi terbaca", value: "\(preview.rowCount)")
            if let first = preview.firstDate, let last = preview.lastDate {
                LabeledContent("Rentang tanggal") {
                    Text("\(first.formatted(.dateTime.day().month(.abbreviated).year())) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))")
                }
            }
            if preview.duplicateCount > 0 {
                Toggle("Lewati \(preview.duplicateCount) transaksi yang sudah ada", isOn: $skipDuplicates)
                    .disabled(outcome != nil)
            }
        }
    }

    private func monthsSection(_ preview: ImportPreview) -> some View {
        Section("Total per bulan") {
            ForEach(preview.months, id: \.self) { month in
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitle(month)).font(.subheadline.weight(.semibold))
                    HStack {
                        Text("Pendapatan \(MoneyFormatter.string(month.income))").foregroundStyle(.blue)
                        Spacer()
                        Text("Pengeluaran \(MoneyFormatter.string(month.expense))").foregroundStyle(.red)
                    }
                    .font(.footnote)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func newItemsSection(_ preview: ImportPreview) -> some View {
        Section {
            if !preview.newAssetNames.isEmpty {
                LabeledContent("Aset baru") { Text(preview.newAssetNames.joined(separator: ", ")).multilineTextAlignment(.trailing) }
            }
            if !preview.newCategoryNames.isEmpty {
                DisclosureGroup("\(preview.newCategoryNames.count) kategori baru") {
                    ForEach(preview.newCategoryNames, id: \.self) { Text($0) }
                }
            }
        } header: {
            Text("Akan dibuat")
        } footer: {
            Text("Kategori dan aset yang namanya sama dengan yang sudah ada dipakai ulang.")
        }
    }

    private func failuresSection(_ failures: [ImportFailure]) -> some View {
        Section("\(failures.count) baris dilewati karena gagal dibaca") {
            ForEach(failures.prefix(20), id: \.line) { failure in
                Text("Baris \(failure.line): \(failure.reason)").font(.footnote)
            }
            if failures.count > 20 { Text("…dan \(failures.count - 20) lainnya").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func importSection(_ preview: ImportPreview) -> some View {
        Section {
            Button("Import \(preview.rowCount - (skipDuplicates ? preview.duplicateCount : 0)) transaksi") { runImport() }
                .bold()
                .disabled(preview.rowCount - (skipDuplicates ? preview.duplicateCount : 0) <= 0)
        }
    }

    private func resultSection(_ outcome: ImportOutcome) -> some View {
        Section {
            Label("\(outcome.imported) transaksi diimpor, \(outcome.skipped) dilewati", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Selesai") { dismiss() }
        } footer: {
            Text("Batal di Lainnya → Riwayat Import.")
        }
    }

    // MARK: Actions

    private func monthTitle(_ month: MonthTotal) -> String {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "id_ID")
        let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        isReading = true
        outcome = nil
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            isReading = false
            errorMessage = "File tidak bisa dibaca."
            return
        }
        let name = url.lastPathComponent
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImportParseResult, Error> in
                Result {
                    let head = data.prefix(64).drop { $0 == 0xEF || $0 == 0xBB || $0 == 0xBF || $0 == 0x20 || $0 == 0x0A || $0 == 0x0D }
                    return head.first == UInt8(ascii: "{") ? try BackupJSONParser.parse(data) : try CSVTransactions.parse(data)
                }
            }.value
            isReading = false
            switch result {
            case .success(let value):
                guard !value.rows.isEmpty else {
                    errorMessage = value.failures.first?.reason ?? "Tidak ada transaksi di file ini."
                    return
                }
                fileName = name
                parsed = value
                skipDuplicates = true
                refreshPreview()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshPreview() {
        guard let parsed, let service else { preview = nil; return }
        preview = try? service.preview(parsed.rows)
    }

    private func runImport() {
        guard let parsed, let service, let fileName, let targetID else { return }
        do {
            let result = try service.commit(parsed.rows, assets: parsed.assets, fileName: fileName, skipDuplicates: skipDuplicates)
            outcome = result
            store.switchTo(targetID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toastCenter.show("\(result.imported) transaksi diimpor")
            refreshPreview()
        } catch ImportServiceError.nothingToImport {
            errorMessage = "Semua transaksi sudah ada di profil ini."
        } catch {
            errorMessage = "Tidak ada data yang tersimpan. \(error.localizedDescription)"
        }
    }
}
