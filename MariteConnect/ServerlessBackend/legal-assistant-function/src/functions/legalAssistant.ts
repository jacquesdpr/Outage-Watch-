import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { verifyCaller } from "../lib/callerIdentity";
import { findRelevantLegalDocuments } from "../lib/legalLibrary";
import { askLegalAssistant, HistoryTurn } from "../lib/claudeClient";

interface RequestBody {
  question: string;
  history: HistoryTurn[];
}

app.http("legalAssistant", {
  methods: ["POST"],
  authLevel: "anonymous", // identity is enforced in-code via the caller's Graph token, see verifyCaller
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const caller = await verifyCaller(request.headers.get("authorization"));
    if (!caller) {
      return { status: 401, jsonBody: { error: "Sign in with your Marite Microsoft 365 account and try again." } };
    }

    let body: RequestBody;
    try {
      body = (await request.json()) as RequestBody;
    } catch {
      return { status: 400, jsonBody: { error: "Invalid request body." } };
    }

    const question = body.question?.trim();
    if (!question) {
      return { status: 400, jsonBody: { error: "A question is required." } };
    }

    try {
      const documents = await findRelevantLegalDocuments(question);
      const answer = await askLegalAssistant(question, body.history ?? [], documents);

      return {
        status: 200,
        jsonBody: {
          answer,
          citations: documents.map((doc) => ({
            documentTitle: doc.documentTitle,
            webUrl: doc.webUrl,
            excerpt: doc.excerpt
          }))
        }
      };
    } catch (error) {
      context.error("legalAssistant failed", error);
      return { status: 500, jsonBody: { error: "The Legal Assistant hit an error. Please try again." } };
    }
  }
});
