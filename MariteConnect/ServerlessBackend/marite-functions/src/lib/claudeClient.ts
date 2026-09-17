import Anthropic from "@anthropic-ai/sdk";
import { requireEnv } from "./graphAuth";
import { LegalDocumentMatch } from "./legalLibrary";

export interface HistoryTurn {
  role: "user" | "assistant";
  text: string;
}

const SYSTEM_PROMPT = `You are the Marite Connect Sectional Title Assistant, used internally by Marite Property Administrators staff.

You help staff interpret South Africa's Sectional Titles Schemes Management Act (STSMA) and its regulations, and CSOS (Community Schemes Ombud Service) adjudication orders, and you help them think through real scenarios at the schemes Marite administers (e.g. a trustee dispute, a levy dispute, a rule enforcement question, a conduct complaint).

Ground every substantive claim in the provided document excerpts. When you rely on an excerpt, cite it by document title. If the excerpts don't cover the question, say so plainly and describe generally how the Act tends to approach that type of issue, clearly flagging that it's general guidance rather than a citation to a specific clause or order — never invent a section number or case reference.

For a described scenario, structure your answer as:
1. The likely legal/procedural issue at play
2. What the Act or a relevant CSOS order says about it
3. Concrete next steps Marite staff should take

You are not a substitute for an attorney; say so if the scenario looks like it needs one (e.g. potential litigation, criminal conduct, large financial exposure).`;

export async function askLegalAssistant(question: string, history: HistoryTurn[], documents: LegalDocumentMatch[]): Promise<string> {
  const client = new Anthropic({ apiKey: requireEnv("ANTHROPIC_API_KEY") });
  const model = process.env.ANTHROPIC_MODEL ?? "claude-sonnet-5";

  const documentContext = documents.length
    ? documents.map((doc, i) => `[Document ${i + 1}: ${doc.documentTitle}]\n${doc.excerpt}`).join("\n\n")
    : "No matching documents were found in the legal library for this question.";

  const response = await client.messages.create({
    model,
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    messages: [
      ...history.map((turn) => ({ role: turn.role, content: turn.text })),
      {
        role: "user" as const,
        content: `Relevant source material:\n\n${documentContext}\n\n---\n\nQuestion: ${question}`
      }
    ]
  });

  return response.content
    .filter((block): block is Anthropic.TextBlock => block.type === "text")
    .map((block) => block.text)
    .join("\n");
}
