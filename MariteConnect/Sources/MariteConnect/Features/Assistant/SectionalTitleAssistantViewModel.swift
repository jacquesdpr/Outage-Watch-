import Foundation

@MainActor
final class SectionalTitleAssistantViewModel: ObservableObject {
    @Published private(set) var messages: [AssistantMessage] = [
        AssistantMessage(
            role: .assistant,
            text: "Hi, I'm the Sectional Title Assistant. Ask me about the Sectional Titles Schemes Management Act, CSOS rulings, or describe a scenario at one of our schemes and I'll help you work out how to handle it — with citations to the actual Act sections or CSOS orders where they apply."
        )
    ]
    @Published var draft = ""
    @Published private(set) var isThinking = false
    @Published var errorMessage: String?

    private let assistantService: AssistantService

    init(assistantService: AssistantService) {
        self.assistantService = assistantService
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }

    func send() async {
        guard canSend else { return }
        let question = draft
        draft = ""
        errorMessage = nil
        messages.append(AssistantMessage(role: .user, text: question))

        isThinking = true
        defer { isThinking = false }
        do {
            let history = messages
            let (answer, citations) = try await assistantService.ask(question: question, history: history)
            messages.append(AssistantMessage(role: .assistant, text: answer, citations: citations))
        } catch {
            errorMessage = "Couldn't reach the Legal Assistant: \(error.localizedDescription)"
        }
    }
}
