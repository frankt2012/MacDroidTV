import SwiftUI
import TVRemoteKit

struct KeyboardInputView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mode: TextInputMode = .ime
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type to the TV")
                .font(.headline)
            Text("Focus a search or text field on the TV first, then type here and press Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Input method", selection: $mode) {
                ForEach(TextInputMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(mode == .ime
                 ? "Try this first. If the text does not appear on the TV, switch to Back first."
                 : "Use this if TV keyboard does not work. It sends Back to dismiss the TV's on-screen keyboard, then types.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Text", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(send)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func send() {
        let value = text
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.sendText(value, mode: mode)
        text = ""
        focused = true
    }
}
