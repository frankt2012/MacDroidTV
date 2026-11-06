import SwiftUI

struct KeyboardInputView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type to the TV")
                .font(.headline)
            Text("Focus a search or text field on the TV first, then type here and press Return.")
                .font(.caption)
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
        model.sendText(value)
        text = ""
        focused = true
    }
}
