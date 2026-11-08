import SwiftUI
import SwiftData
import MoneyCore

/// Add or edit one transaction: type, date, amount via calculator keypad,
/// category/asset pickers, note with suggestions and description.
struct TransactionFormView: View {
    enum Mode {
        case create(defaultDate: Date)
        case edit(MoneyTransaction)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var store
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var draft: TransactionDraft
    @State private var amountExpression: String
    @State private var feeExpression: String
    /// Field driven by the keypad or a picker sheet; `nil` when neither is active.
    @State private var activeField: Field?
    @State private var picker: PickerTarget?
    @State private var showsAmountError = false
    @State private var showsFeeError = false
    @State private var isConfirmingDelete = false
    /// Set when a picker closes the quick flow; the note gets focus once the sheet is gone.
    @State private var focusesNoteAfterPicker = false
    @State private var appliedProfileDefaults = false
    @State private var isPickingFavorite = false
    @State private var isNamingFavorite = false
    @State private var favoriteName = ""
    @State private var favoriteError: String?
    @FocusState private var textFocus: TextFocus?

    private enum Field { case amount, fee }
    private enum TextFocus { case note, detail }

    private enum PickerTarget: Identifiable {
        case category, asset, fromAsset, toAsset
        var id: Self { self }
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let date):
            _draft = State(initialValue: TransactionDraft(type: .expense, date: date))
            _amountExpression = State(initialValue: "")
            _feeExpression = State(initialValue: "")
            _activeField = State(initialValue: .amount)
        case .edit(let tx):
            _draft = State(initialValue: TransactionDraft(from: tx))
            _amountExpression = State(initialValue: Self.expression(for: tx.amount))
            _feeExpression = State(initialValue: Self.expression(for: tx.fee))
            _activeField = State(initialValue: nil)
        }
    }

    // MARK: Derived

    private var profileID: UUID? {
        switch mode {
        case .create: store.activeProfileID
        case .edit(let tx): tx.profileID
        }
    }

    private var profile: Profile? { profiles.first { $0.id == profileID } }

    private var service: TransactionService? {
        profileID.map { TransactionService(context: context, profileID: $0) }
    }

    private var amountResult: Result<Decimal, AmountParserError> {
        Result { () throws(AmountParserError) in try AmountParser.evaluate(amountExpression) }
    }

    private var feeResult: Result<Decimal, AmountParserError> {
        // An empty fee means no fee.
        feeExpression.isEmpty ? .success(0) : Result { () throws(AmountParserError) in try AmountParser.evaluate(feeExpression) }
    }

    /// Draft with the evaluated keypad values applied, or `nil` while an expression is invalid.
    private var resolvedDraft: TransactionDraft? {
        guard case .success(let amount) = amountResult, case .success(let fee) = feeResult else { return nil }
        var d = draft
        d.amount = amount
        d.fee = draft.type == .transfer ? fee : 0
        return d
    }

    private var canSave: Bool {
        guard let d = resolvedDraft, let service else { return false }
        do { try service.validate(d); return true } catch { return false }
    }

    private var title: String {
        switch draft.type {
        case .income: "Pendapatan"
        case .transfer: "Transfer"
        case .expense, .adjustment: "Pengeluaran"
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Picker("Jenis", selection: typeBinding) {
                            Text("Pendapatan").tag(TransactionType.income)
                            Text("Pengeluaran").tag(TransactionType.expense)
                            Text("Transfer").tag(TransactionType.transfer)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section {
                        DatePicker("Tanggal", selection: $draft.date)
                            .environment(\.locale, Locale(identifier: "id_ID"))
                        amountRow(
                            title: "Total",
                            expression: amountExpression,
                            result: amountResult,
                            field: .amount,
                            showsError: showsAmountError
                        )
                        if draft.type == .transfer {
                            pickerRow("Dari", value: assetName(draft.assetID), picker: .fromAsset)
                            pickerRow("Ke", value: assetName(draft.toAssetID), picker: .toAsset)
                            amountRow(
                                title: "Biaya",
                                expression: feeExpression,
                                result: feeResult,
                                field: .fee,
                                showsError: showsFeeError
                            )
                        } else {
                            pickerRow("Kategori", value: categoryText, picker: .category)
                            pickerRow("Aset", value: assetName(draft.assetID), picker: .asset)
                        }
                    }

                    Section {
                        TextField("Catatan", text: $draft.note)
                            .focused($textFocus, equals: .note)
                            .id(TextFocus.note)
                            // Short everyday labels ("makan siang"); suggestions do the completing.
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .onSubmit { textFocus = .detail }
                        TextField("Deskripsi", text: $draft.detail, axis: .vertical)
                            .focused($textFocus, equals: .detail)
                            .lineLimit(2...6)
                    }

                    if case .edit(let tx) = mode {
                        Section {
                            Button("Duplikat", systemImage: "plus.square.on.square") { duplicate(tx) }
                            Button("Simpan sebagai favorit", systemImage: "star") { startSavingFavorite() }
                                .disabled(resolvedDraft == nil)
                            Button("Hapus", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        }
                    }
                }
                // Keeps the row the keypad is editing clear of the keypad panel.
                .onChange(of: activeField) { _, field in
                    guard let field else { return }
                    withAnimation { proxy.scrollTo(field, anchor: .center) }
                }
                // Keeps the note and its suggestion bar clear of the keyboard.
                // The form's own keyboard avoidance ignores the suggestion bar on top of the keyboard.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    guard textFocus == .note else { return }
                    withAnimation { proxy.scrollTo(TextFocus.note, anchor: .center) }
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(profile.map { "Profil: \($0.name)" } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
            .onChange(of: textFocus) { _, focus in
                if focus != nil { activeField = nil }
            }
            .onAppear(perform: applyProfileDefaults)
            .sheet(item: $picker, onDismiss: {
                guard focusesNoteAfterPicker else { return }
                focusesNoteAfterPicker = false
                textFocus = .note
            }) { picker in
                pickerSheet(picker)
            }
            .sheet(isPresented: $isPickingFavorite) {
                if let profileID { FavoritePickerSheet(profileID: profileID, onPick: applyFavorite) }
            }
            .alert("Simpan sebagai favorit", isPresented: $isNamingFavorite) {
                TextField("Nama favorit", text: $favoriteName)
                Button("Simpan dengan nominal") { saveFavorite(includeAmount: true) }
                Button("Simpan tanpa nominal") { saveFavorite(includeAmount: false) }
                Button("Batal", role: .cancel) {}
            } message: {
                Text("Jenis, kategori, aset, dan catatan disimpan sebagai template.")
            }
            .alert("Gagal menyimpan favorit", isPresented: Binding(get: { favoriteError != nil }, set: { if !$0 { favoriteError = nil } })) {
                Button("OK") { favoriteError = nil }
            } message: {
                Text(favoriteError ?? "")
            }
            .confirmationDialog("Hapus transaksi ini?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Hapus", role: .destructive) {
                    if case .edit(let tx) = mode { delete(tx) }
                }
            } message: {
                Text("Transaksi yang dihapus tidak bisa dikembalikan.")
            }
        }
        .tint(Color(hex: profile?.colorHex ?? "#FF6B5A"))
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Batal") { dismiss() }
        }
        if case .create = mode {
            ToolbarItem(placement: .primaryAction) {
                Button("Favorit", systemImage: "star") { isPickingFavorite = true }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Simpan", action: save)
                .disabled(!canSave)
        }
        if textFocus == .note {
            ToolbarItem(placement: .keyboard) { noteSuggestions }
        }
    }

    // MARK: Rows

    private func amountRow(
        title: String,
        expression: String,
        result: Result<Decimal, AmountParserError>,
        field: Field,
        showsError: Bool
    ) -> some View {
        let isActive = activeField == field
        let error = errorMessage(expression: expression, result: result, forced: showsError)
        return Button {
            activate(field)
        } label: {
            VStack(alignment: .trailing, spacing: 4) {
                LabeledContent(title) {
                    Text(displayText(expression: expression, result: result, isActive: isActive))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(expression.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.08) : nil)
        .accessibilityValue(error ?? "")
        .id(field)
    }

    private func pickerRow(_ title: String, value: String?, picker target: PickerTarget) -> some View {
        Button {
            textFocus = nil
            activeField = nil
            picker = target
        } label: {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    Text(value ?? "Pilih")
                        .foregroundStyle(value == nil ? .tertiary : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(picker == target ? Color.accentColor.opacity(0.08) : nil)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        let keypadField = picker == nil ? activeField : nil
        // Hidden while the system keyboard is up; it would ride above it and cover the field.
        if textFocus == nil {
            VStack(spacing: 0) {
                if let field = keypadField {
                    CalculatorKeypad(
                        expression: field == .amount ? $amountExpression : $feeExpression,
                        onEquals: { evaluate(field, confirming: false) },
                        onConfirm: { evaluate(field, confirming: true) }
                    )
                    .onChange(of: amountExpression) { showsAmountError = false }
                    .onChange(of: feeExpression) { showsFeeError = false }
                    .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity)
            .background(.background)
            .animation(.snappy, value: keypadField)
        }
    }

    @ViewBuilder
    private var noteSuggestions: some View {
        let items = noteSuggestionItems
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { text in
                        Button(text) {
                            draft.note = text
                            textFocus = .detail
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityHint("Isi catatan")
                    }
                }
            }
        }
    }

    private var noteSuggestionItems: [String] {
        guard let profileID else { return [] }
        let all = (try? NoteSuggester(context: context, profileID: profileID)
            .suggestions(prefix: draft.note, categoryID: draft.categoryID)) ?? []
        return all.filter { $0 != draft.note }
    }

    @ViewBuilder
    private func pickerSheet(_ target: PickerTarget) -> some View {
        if let profileID {
            switch target {
            case .category:
                CategoryPickerSheet(
                    profileID: profileID,
                    kind: draft.type == .income ? .income : .expense,
                    selectedID: draft.categoryID
                ) { category in
                    draft.categoryID = category.id
                    // Quick flow: go straight on to the asset unless one is already set, then to the note.
                    if draft.assetID == nil {
                        picker = .asset
                    } else {
                        finishPickerFlow()
                    }
                }
            case .asset, .fromAsset, .toAsset:
                AssetPickerSheet(
                    profileID: profileID,
                    title: target == .toAsset ? "Ke" : target == .fromAsset ? "Dari" : "Aset",
                    selectedID: target == .toAsset ? draft.toAssetID : draft.assetID
                ) { asset in
                    if target == .toAsset {
                        draft.toAssetID = asset.id
                        finishPickerFlow()
                    } else {
                        draft.assetID = asset.id
                        if target == .fromAsset && draft.toAssetID == nil {
                            picker = .toAsset
                        } else {
                            finishPickerFlow()
                        }
                    }
                }
            }
        }
    }

    // MARK: Display helpers

    private var categoryText: String? {
        guard let id = draft.categoryID, let category = fetchCategory(id) else { return nil }
        let top = category.parent ?? category
        let emoji = top.emoji.isEmpty ? "" : "\(top.emoji) "
        if let parent = category.parent { return "\(emoji)\(parent.name) › \(category.name)" }
        return "\(emoji)\(category.name)"
    }

    private func assetName(_ id: UUID?) -> String? {
        guard let id, let profileID else { return nil }
        var descriptor = FetchDescriptor<AssetAccount>(predicate: #Predicate { $0.id == id && $0.profileID == profileID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.name
    }

    private func fetchCategory(_ id: UUID) -> MoneyCategory? {
        guard let profileID else { return nil }
        var descriptor = FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.id == id && $0.profileID == profileID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Expression with thousands dots while typing; the formatted amount otherwise.
    private func displayText(expression: String, result: Result<Decimal, AmountParserError>, isActive: Bool) -> String {
        if expression.isEmpty { return "Rp 0" }
        if !isActive, case .success(let value) = result { return MoneyFormatter.string(value) }
        return "Rp " + Self.groupingDigits(expression)
    }

    /// `"12500+3000,5"` → `"12.500+3.000,5"`: dots every three digits in each number's integer part.
    static func groupingDigits(_ expression: String) -> String {
        var output = ""
        var digits = ""
        var inFraction = false
        func flush() {
            guard !digits.isEmpty else { return }
            if inFraction {
                output += digits
            } else {
                for (index, digit) in digits.enumerated() {
                    if index > 0, (digits.count - index) % 3 == 0 { output += "." }
                    output.append(digit)
                }
            }
            digits = ""
        }
        for character in expression {
            if character.isNumber {
                digits.append(character)
            } else {
                flush()
                output.append(character)
                inFraction = character == ","
            }
        }
        flush()
        return output
    }

    /// Errors show once the expression looks complete (or after `=`/`Ya`), not mid-typing like `12+`.
    private func errorMessage(expression: String, result: Result<Decimal, AmountParserError>, forced: Bool) -> String? {
        guard !expression.isEmpty, case .failure(let error) = result else { return nil }
        let looksComplete = expression.last.map { !"+-×÷,".contains($0) } ?? false
        guard forced || looksComplete else { return nil }
        switch error {
        case .divisionByZero: return "Tidak bisa dibagi nol"
        case .tooLarge: return "Nominal terlalu besar"
        case .empty, .malformed: return "Format tidak valid"
        }
    }

    /// `1280.5` → `"1280,5"`; zero → empty.
    private static func expression(for amount: Decimal) -> String {
        amount == 0 ? "" : "\(amount)".replacingOccurrences(of: ".", with: ",")
    }

    /// Blocks swipe-to-dismiss once something was entered, so a stray swipe doesn't lose it.
    private var hasChanges: Bool {
        switch mode {
        case .create: !amountExpression.isEmpty || !draft.note.isEmpty || !draft.detail.isEmpty
        case .edit(let tx): (resolvedDraft ?? draft) != TransactionDraft(from: tx)
        }
    }

    // MARK: Actions

    private var typeBinding: Binding<TransactionType> {
        Binding {
            draft.type
        } set: { newType in
            guard newType != draft.type else { return }
            let oldKind: CategoryKind = draft.type == .income ? .income : .expense
            let newKind: CategoryKind = newType == .income ? .income : .expense
            if newType == .transfer || oldKind != newKind { draft.categoryID = nil }
            if newType != .transfer { draft.toAssetID = nil }
            draft.type = newType
        }
    }

    /// Closes the picker; an empty note gets focus next, so the entry flows date → total → category → asset → note.
    private func finishPickerFlow() {
        focusesNoteAfterPicker = draft.note.isEmpty
        picker = nil
    }

    /// New entries open on the type the profile records most: income for a business, expense otherwise.
    private func applyProfileDefaults() {
        guard !appliedProfileDefaults, case .create = mode, let profile else { return }
        appliedProfileDefaults = true
        if profile.kind == .business { draft.type = .income }
    }

    private func activate(_ field: Field) {
        textFocus = nil
        picker = nil
        activeField = field
    }

    private func evaluate(_ field: Field, confirming: Bool) {
        let expression = field == .amount ? amountExpression : feeExpression
        let result = field == .amount ? amountResult : feeResult
        guard case .success(let value) = result else {
            if field == .amount { showsAmountError = true } else { showsFeeError = true }
            return
        }
        if value >= 0, !expression.isEmpty {
            let normalized = Self.expression(for: value)
            if field == .amount { amountExpression = normalized } else { feeExpression = normalized }
        }
        guard confirming else { return }
        activeField = nil
        guard field == .amount else { return }
        switch draft.type {
        case .transfer:
            if draft.assetID == nil { picker = .fromAsset } else if draft.toAssetID == nil { picker = .toAsset }
        default:
            if draft.categoryID == nil { picker = .category } else if draft.assetID == nil { picker = .asset }
        }
    }

    private func save() {
        guard let d = resolvedDraft, let service else { return }
        do {
            switch mode {
            case .create: try service.create(d)
            case .edit(let tx): try service.update(tx, with: d)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            assertionFailure("Simpan transaksi gagal: \(error)")
        }
    }

    private func applyFavorite(_ favorite: FavoriteTemplate) {
        guard let profileID else { return }
        do {
            try FavoriteService(context: context, profileID: profileID).apply(favorite, to: &draft)
            if favorite.amount != nil {
                amountExpression = Self.expression(for: draft.amount)
                showsAmountError = false
            }
            activeField = favorite.amount == nil ? .amount : nil
            UISelectionFeedbackGenerator().selectionChanged()
        } catch {
            favoriteError = "Favorit tidak bisa dipakai di profil ini."
        }
    }

    private func startSavingFavorite() {
        favoriteName = draft.note.isEmpty ? (draft.categoryID.flatMap(fetchCategory)?.name ?? "") : draft.note
        isNamingFavorite = true
    }

    private func saveFavorite(includeAmount: Bool) {
        guard let profileID else { return }
        var template = resolvedDraft ?? draft
        template.date = draft.date
        do {
            try FavoriteService(context: context, profileID: profileID)
                .create(name: favoriteName, from: template, includeAmount: includeAmount)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch FavoriteServiceError.emptyName {
            favoriteError = "Nama favorit tidak boleh kosong."
        } catch {
            favoriteError = error.localizedDescription
        }
    }

    private func duplicate(_ tx: MoneyTransaction) {
        do {
            try service?.duplicate(tx, on: .now)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            assertionFailure("Duplikat transaksi gagal: \(error)")
        }
    }

    private func delete(_ tx: MoneyTransaction) {
        do {
            try service?.delete(tx)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            assertionFailure("Hapus transaksi gagal: \(error)")
        }
    }
}
