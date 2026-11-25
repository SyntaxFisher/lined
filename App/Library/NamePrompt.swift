import LinedModel
import SwiftUI

/// A request to ask the user for a name, and what to do with the answer.
struct NamePrompt: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let initialName: String
    let commit: (String) -> Void

    static func newFolder(in parentID: Folder.ID?, of library: LibraryModel) -> NamePrompt {
        NamePrompt(title: "New Folder", actionTitle: "Create", initialName: "") { name in
            library.perform { try library.createFolder(named: name, in: parentID) }
        }
    }

    static func rename(_ item: LibraryEntry, in library: LibraryModel) -> NamePrompt {
        NamePrompt(title: "Rename", actionTitle: "Rename", initialName: item.name) { name in
            library.perform { try library.rename(item.id, to: name) }
        }
    }
}

extension View {
    /// Asks for a name in an alert whenever `prompt` holds a request.
    func namePrompt(_ prompt: Binding<NamePrompt?>) -> some View {
        modifier(NamePromptAlert(prompt: prompt))
    }
}

private struct NamePromptAlert: ViewModifier {
    @Binding var prompt: NamePrompt?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(prompt?.title ?? "", isPresented: isPresented, presenting: prompt) { prompt in
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button(prompt.actionTitle) { prompt.commit(name) }
            }
            .onChange(of: prompt?.id) {
                name = prompt?.initialName ?? ""
            }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            prompt != nil
        } set: { isPresented in
            if !isPresented { prompt = nil }
        }
    }
}
