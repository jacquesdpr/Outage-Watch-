import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { verifyCaller } from "../lib/callerIdentity";
import { registerDeviceToken } from "../lib/deviceTokenStore";

interface RequestBody {
  deviceToken: string;
}

/**
 * Called once after sign-in (and again whenever iOS hands the app a new APNs
 * token) so the backend knows where to push "you've been tagged" alerts.
 */
app.http("registerDevice", {
  methods: ["POST"],
  authLevel: "anonymous", // identity enforced via verifyCaller, same pattern as legalAssistant
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

    if (!body.deviceToken) {
      return { status: 400, jsonBody: { error: "deviceToken is required." } };
    }

    try {
      await registerDeviceToken(caller.id, caller.displayName, body.deviceToken);
      return { status: 204 };
    } catch (error) {
      context.error("registerDevice failed", error);
      return { status: 500, jsonBody: { error: "Could not register this device." } };
    }
  }
});
