import SwiftUI
import SwiftData
import MoneyCore

/// Add or edit one asset: name, group, opening balance via calculator keypad,
/// whether it counts toward the total, and (when editing) archiving.
struct AssetFormView: View {
    enum Mode {
        case create
        case edit(AssetAccount)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var store
    @Query(sort: [SortDescriptor(\Profile.sortOrder), SortDescriptor(\Profile.createdAt)]) private var profiles: [Profile]

    @State private var name: String
    @State private var group: AssetGroup
    @State private var balanceExpression: String
    @State private var includeInTotal: Bool
    @State private var isArchived: Bool
    @State private var isKeypadActive = false
    @State private var showsBalanceError = false
    @FocusState private var isNameFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _group = State(initialValue: .cash)
            _balanceExpression = State(initialValue: "")
            _includeInTotal = State(initialValue: true)
            _isArchived = State(initialValue: false)
        case .edit(let asset):
            _name = State(initialValue: asset.name)
            _group = State(initialValue: asset.group)
            _balanceExpression = State(initialValue: BalanceExpression.expression(for: asset.initialBalance))
            _includeInTotal = State(initialValue: asset.includeInTotal)
            _isArchived = State(initialValue: asset.isArchived)
        }
    }

    // MARK: Derived

    private var profileID: UUID? {
        switch mode {
        case .create: store.activeProfileID
        case .edit(let asset): asset.profileID
        }
    }

    private var profile: Profile? { profiles.first { $0.id == profileID } }

    private var service: AssetService? {
        profileID.map { AssetService(context: context, profileID: $0) }
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    /// An empty expression is an opening balance of zero.
    private var balanceResult: Result<Decimal, AmountParserError> {
        balanceExpression.isEmpty ? .success(0) : BalanceExpression.evaluate(balanceExpression)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, case .success = balanceResult else { return false }
        return service != nil
    }

    /// Blocks swipe-to-dismiss once something was entered, so a stray swipe doesn't lose it.
    private var hasChanges: Bool {
        switch mode {
        case .create:
            return !name.isEmpty || !balanceExpression.isEmpty
        case .edit(let asset):
            guard case .success(let balance) = balanceResult else { return true }
            return trimmedName != asset.name || group != asset.group || balance != asset.initialBalance
                || includeInTotal != asset.includeInTotal || isArchived != asset.isArchived
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nama", text: $name)
                        .focused($isNameFocused)
                        // Proper names (BCA, GoPay) that autocorrect would mangle.
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    Picker("Grup", selection: $group) {
                        ForEach(AssetGroup.allCases, id: \.self) { Text($0.displayName) }
                    }
                    .pickerStyle(.menu)
                    BalanceAmountRow(
                        title: "Saldo awal",
                        expression: balanceExpression,
                        result: balanceResult,
                        isActive: isKeypadActive,
                        showsError: showsBalanceError,
                        onTap: activateKeypad
                    )
                } footer: {
                    Text("Untuk utang, awali dengan tanda minus, misalnya -500000.")
                }

                Section {
                    Toggle("Masukkan ke total", isOn: $includeInTotal)
                } footer: {
                    Text("Jika dimatikan, saldo aset ini tidak dihitung di Aset, Liabilitas, dan Total.")
                }

                if isEditing {
                    Section {
                        Toggle("Arsipkan aset", isOn: $isArchived)
                    } footer: {
                        Text("Aset arsip tidak muncul di pilihan input, tapi transaksinya tetap ada.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Ubah aset" : "Aset baru")
            .navigationSubtitle(profile.map { "Profil: \($0.name)" } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
            .onChange(of: isNameFocused) { _, focused in
                if focused { isKeypadActive = false }
            }
            .onChange(of: balanceExpression) { showsBalanceError = false }
            .onAppear { isNameFocused = !isEditing }
        }
        .tint(Color(hex: profile?.colorHex ?? "#FF6B5A"))
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if isKeypadActive {
            CalculatorKeypad(
                expression: $balanceExpression,
                onEquals: { evaluate(confirming: false) },
                onConfirm: { evaluate(confirming: true) }
            )
            .frame(maxWidth: .infinity)
            .background(.background)
            .transition(.move(edge: .bottom))
            .animation(.snappy, value: isKeypadActive)
        }
    }

    // MARK: Actions

    private func activateKeypad() {
        isNameFocused = false
        isKeypadActive = true
    }

    private func evaluate(confirming: Bool) {
        guard case .success(let value) = balanceResult else {
            showsBalanceError = true
            return
        }
        if !balanceExpression.isEmpty { balanceExpression = BalanceExpression.expression(for: value) }
        if confirming { isKeypadActive = false }
    }

    private func save() {
        guard canSave, case .success(let balance) = balanceResult, let service else { return }
        do {
            switch mode {
            case .create:
                let asset = try service.create(name: trimmedName, group: group, initialBalance: balance)
                // `create` makes an active asset counted in the total; only differences need an update.
                if !includeInTotal {
                    try service.update(
                        asset, name: trimmedName, group: group, initialBalance: balance,
                        includeInTotal: false, isArchived: false
                    )
                }
            case .edit(let asset):
                try service.update(
                    asset, name: trimmedName, group: group, initialBalance: balance,
                    includeInTotal: includeInTotal, isArchived: isArchived
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            assertionFailure("Simpan aset gagal: \(error)")
            return
        }
        dismiss()
    }
}
