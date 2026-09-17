import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { verifyCaller } from "../lib/callerIdentity";
import { unregisterDeviceToken } from "../lib/deviceTokenStore";

interface RequestBody {
  deviceToken: string;
}

/** Called on sign-out so a shared or reissued device stops receiving a former user's pushes. */
app.http("unregisterDevice", {
  methods: ["POST"],
  authLevel: "anonymous",
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
      await unregisterDeviceToken(caller.id, body.deviceToken);
      return { status: 204 };
    } catch (error) {
      context.error("unregisterDevice failed", error);
      return { status: 500, jsonBody: { error: "Could not unregister this device." } };
    }
  }
});
