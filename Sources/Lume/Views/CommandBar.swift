import SwiftUI

/// One thing the command bar can do.
struct Command: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String? = nil
    /// Other words it answers to, such as "memory" for Free RAM.
    var keywords = ""
    let run: () -> Void
}

/// ⌘K: a small glass palette over the window. Type to filter, arrows to move, Return to run, Esc to close.
struct CommandBar: View {
    let commands: [Command]
    let close: () -> Void
    @StateObject private var query = ViewState("")
    @StateObject private var selection = ViewState(0)
    @FocusState private var focused: Bool

    private var matches: [Command] {
        let text = query.value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return commands }
        return commands
            .compactMap { command in
                (Self.score(text, command.title) ?? Self.score(text, command.keywords).map { $0 - 2 })
                    .map { (command, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        let matches = matches
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                TextField("Go to or do…", text: $query.value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .onSubmit { run(matches) }
                    .onKeyPress(.downArrow) { move(1, in: matches); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: matches); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)

            if !matches.isEmpty {
                Hairline()
                VStack(spacing: 2) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                        row(command, selected: index == selection.value)
                            .onTapGesture { selection.value = index; run(matches) }
                            .onHover { if $0 { selection.value = index } }
                    }
                }
                .padding(6)
            } else {
                Hairline()
                Text("No matches")
                    .font(Theme.body)
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
            }
        }
        .frame(width: 480)
        // Tinted nearly white, so the page beneath doesn't read through the list.
        .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: Color.white.opacity(0.7))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
        .task {
            // Focus once the field is in the window; on the first frame it isn't yet.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
        .onChange(of: query.value) { selection.value = 0 }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command bar")
    }

    private func row(_ command: Command, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20)
            Text(command.title).font(Theme.body)
            Spacer()
            if let shortcut = command.shortcut {
                Text(shortcut).font(Theme.caption).foregroundStyle(Theme.tertiary)
            }
        }
        .foregroundStyle(selected ? Theme.accent : Theme.ink)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(selected ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func move(_ step: Int, in matches: [Command]) {
        guard !matches.isEmpty else { return }
        selection.value = (selection.value + step + matches.count) % matches.count
    }

    private func run(_ matches: [Command]) {
        guard matches.indices.contains(selection.value) else { return }
        let command = matches[selection.value]
        close()
        command.run()
    }

    /// Letters of the query in order anywhere in the title; word starts and a leading match score higher.
    /// Nil when the letters don't all appear.
    static func score(_ query: String, _ title: String) -> Int? {
        let query = Array(query.lowercased().filter { !$0.isWhitespace })
        let title = Array(title.lowercased())
        var score = 0, position = 0, previous = -2
        for letter in query {
            guard let found = title[position...].firstIndex(of: letter) else { return nil }
            if found == 0 || title[found - 1] == " " { score += 3 }
            if found == previous + 1 { score += 2 }
            score += 1
            previous = found
            position = found + 1
        }
        return score - title.count / 8
    }
}
