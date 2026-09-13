// Sends an FCM push to one user. Runs server-side so the Firebase service
// account never ships in the app, and the recipient's fcm_token is read
// with the service role (client RLS can only see the caller's own profile).
//
// Request (authenticated admin with `notifications.send`): { user_id, title,
// body, data? }
//
// Restricted to admins holding the same permission send-campaign requires.
// Every event-triggered push in this app (order status, chat, support,
// settlements, reports) goes through its own *-notify function, called by a
// database trigger with a shared secret rather than a user's JWT — this
// function is for an admin messaging one person directly, and previously had
// no such check: any signed-in user could push arbitrary title/body/data,
// including a deep-link route, to any user id.
//
// Secrets required:
//   FIREBASE_SA_B64 — base64 of the service-account JSON
//     ({ project_id, client_email, private_key })
import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const saB64 = Deno.env.get("FIREBASE_SA_B64");
    if (!saB64) return json({ error: "PUSH_NOT_CONFIGURED" }, 503);
    const sa = JSON.parse(atob(saB64));

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData.user) return json({ error: "UNAUTHORIZED" }, 401);

    // The caller's own permission decides this, not the service role the
    // function runs with — otherwise any signed-in user could reach it.
    const caller = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: allowed } = await caller.rpc("has_permission", {
      p_key: "notifications.send",
    });
    if (allowed !== true) return json({ error: "FORBIDDEN" }, 403);

    const body = await req.json().catch(() => ({}));
    const userId = body.user_id;
    const title = `${body.title ?? ""}`.slice(0, 200);
    const message = `${body.body ?? ""}`.slice(0, 500);
    if (!userId || typeof userId !== "string" || !title) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }

    const { data: profile } = await admin
      .from("profiles")
      .select("fcm_token")
      .eq("id", userId)
      .maybeSingle();

    const fcmToken = profile?.fcm_token;
    if (!fcmToken) return json({ sent: false, reason: "NO_TOKEN" });

    const authClient = new JWT({
      email: sa.client_email,
      key: sa.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const { token: accessToken } = await authClient.getAccessToken();

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body: message },
            data: body.data ?? {},
          },
        }),
      },
    );

    if (!fcmRes.ok) {
      const detail = await fcmRes.text();
      console.error("FCM send failed", fcmRes.status, detail);
      // A dead token should not break callers; clear it so we stop trying.
      if (fcmRes.status === 404 || fcmRes.status === 410) {
        await admin.from("profiles")
          .update({ fcm_token: null })
          .eq("id", userId);
      }
      return json({ sent: false, reason: "FCM_ERROR" });
    }

    return json({ sent: true });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
