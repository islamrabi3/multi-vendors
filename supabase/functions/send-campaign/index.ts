// Sends one composed announcement to a whole audience.
//
// The per-event pushes are fired by triggers, one recipient at a time. This is
// the other shape: an admin writes a message once and it goes to everybody who
// can receive it. Runs server-side for the same reason send-push does — the
// Firebase service account must never ship in the app, and the recipients'
// tokens are readable only with the service role.
//
// Request (authenticated admin with `notifications.send`): { campaign_id }
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

// FCM has no true multicast in the v1 API — each token is its own request — so
// they go out in bounded waves. Wide enough to finish a large audience in
// seconds, narrow enough not to trip FCM's per-project rate limits.
const BATCH_SIZE = 100;

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

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let campaignId: string | null = null;

  try {
    const saB64 = Deno.env.get("FIREBASE_SA_B64");
    if (!saB64) return json({ error: "PUSH_NOT_CONFIGURED" }, 503);
    const sa = JSON.parse(atob(saB64));

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
    campaignId = body.campaign_id ?? null;
    if (!campaignId) return json({ error: "INVALID_REQUEST" }, 400);

    const { data: campaign } = await admin
      .from("notification_campaigns")
      .select("*")
      .eq("id", campaignId)
      .maybeSingle();
    if (!campaign) return json({ error: "NOT_FOUND" }, 404);
    // Sending twice would double every user's inbox; the status is the lock.
    if (campaign.status === "sent" || campaign.status === "sending") {
      return json({ error: "ALREADY_SENT" }, 409);
    }

    await admin
      .from("notification_campaigns")
      .update({ status: "sending" })
      .eq("id", campaignId);

    const { data: recipients } = await admin.rpc("campaign_recipients", {
      p_audience: campaign.audience,
    });
    const targets: { user_id: string; fcm_token: string }[] = recipients ?? [];

    const authClient = new JWT({
      email: sa.client_email,
      key: sa.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const { token: accessToken } = await authClient.getAccessToken();
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let delivered = 0;
    let failed = 0;
    const deadTokens: string[] = [];

    for (let i = 0; i < targets.length; i += BATCH_SIZE) {
      const batch = targets.slice(i, i + BATCH_SIZE);
      const results = await Promise.all(batch.map(async (target) => {
        try {
          const res = await fetch(endpoint, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${accessToken}`,
            },
            body: JSON.stringify({
              message: {
                token: target.fcm_token,
                notification: { title: campaign.title, body: campaign.body },
                // `route` is the key the app already reads to decide where a
                // tapped notification lands.
                data: campaign.deep_link
                  ? { route: campaign.deep_link }
                  : {},
              },
            }),
          });
          if (res.ok) return { ok: true, dead: false };
          // 404/410 mean the app was uninstalled or the token rotated. Keeping
          // it would mean retrying a dead address on every future campaign.
          return { ok: false, dead: res.status === 404 || res.status === 410 };
        } catch (_) {
          return { ok: false, dead: false };
        }
      }));

      for (let j = 0; j < results.length; j++) {
        if (results[j].ok) {
          delivered++;
        } else {
          failed++;
          if (results[j].dead) deadTokens.push(batch[j].user_id);
        }
      }
    }

    if (deadTokens.length > 0) {
      await admin
        .from("profiles")
        .update({ fcm_token: null })
        .in("id", deadTokens);
    }

    // The inbox copy is what survives a swiped-away push, and it goes to the
    // whole audience rather than only to reachable devices.
    await admin.rpc("record_campaign_notifications", {
      p_campaign_id: campaignId,
    });

    await admin
      .from("notification_campaigns")
      .update({
        status: "sent",
        recipients: targets.length,
        delivered,
        failed,
        sent_at: new Date().toISOString(),
      })
      .eq("id", campaignId);

    return json({ sent: true, recipients: targets.length, delivered, failed });
  } catch (error) {
    console.error(error);
    // A campaign stuck on "sending" would be unsendable forever, so a failure
    // is recorded on the row rather than only in the logs.
    if (campaignId) {
      await admin
        .from("notification_campaigns")
        .update({ status: "failed", error: `${error}`.slice(0, 500) })
        .eq("id", campaignId);
    }
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
