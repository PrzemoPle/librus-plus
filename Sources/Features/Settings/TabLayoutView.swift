import SwiftUI

/// Settings → Zakładki: pick which three screens sit in the tab bar between
/// Pulpit and Więcej. Everything else stays reachable from Więcej.
struct TabLayoutView: View {
    @Environment(TabLayout.self) private var layout

    var body: some View {
        List {
            Section {
                fixedRow(.dashboard)
                ForEach(0..<TabLayout.slots, id: \.self) { slot in
                    slotRow(slot)
                }
                fixedRow(.more)
            } header: {
                Text("Pasek zakładek")
            } footer: {
                Text("Pulpit i Więcej są zawsze na miejscu. Wybierając ekran, który już jest w pasku, zamieniasz je miejscami.")
            }

            Section {
                ForEach(layout.inMore) { tab in
                    Label {
                        Text(tab.longTitle)
                    } icon: {
                        Image(systemName: tab.systemImage)
                            .foregroundStyle(tab.tint)
                    }
                }
            } header: {
                Text("W zakładce Więcej")
            }

            if !layout.isDefault {
                Section {
                    Button {
                        Haptics.selection()
                        layout.reset()
                    } label: {
                        Label("Przywróć domyślny układ", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Zakładki")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fixedRow(_ tab: MainTab) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: tab.systemImage)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(tab.longTitle)
            Spacer()
            Text("stała")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(tab.longTitle), zakładka stała")
    }

    private func slotRow(_ slot: Int) -> some View {
        let current = layout.bar[slot]
        return Picker(selection: Binding(
            get: { current },
            set: { newValue in
                Haptics.selection()
                layout.set(slot: slot, to: newValue)
            }
        )) {
            ForEach(MainTab.placeable) { tab in
                Label(tab.longTitle, systemImage: tab.systemImage).tag(tab)
            }
        } label: {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: current.systemImage)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                Text("Zakładka \(slot + 2)")
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Zakładka \(slot + 2): \(current.longTitle)")
    }
}
