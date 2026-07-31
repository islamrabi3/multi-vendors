// Complaint push notifications, driven by the notify_report_event trigger.
//
// new_report      -> every admin (someone needs to pick this up)
// report_replied  -> the customer who raised it
// report_resolved -> the customer who raised it
//
// Authenticated with the same shared secret as order-notify, since the caller
// is the database rather than a signed-in user. Each recipient is messaged in
// the language they read the UI in (`profiles.locale`).
//
// Secrets required: FIREBASE_SA_B64, ORDER_NOTIFY_SECRET
import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

type Lang = "en" | "ar";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const COPY: Record<string, Record<Lang, { title: string; body: string }>> = {
  new_report: {
    en: { title: "New complaint 📣", body: "A customer reported: " },
    ar: { title: "شكوى جديدة 📣", body: "بلاغ من عميل: " },
  },
  report_replied: {
    en: { title: "Support replied 💬", body: "We answered your report: " },
    ar: { title: "رد الدعم 💬", body: "تم الرد على بلاغك: " },
  },
  report_resolved: {
    en: { title: "Complaint resolved ✅", body: "Your report was resolved: " },
    ar: { title: "تم حل الشكوى ✅", body: "تم حل بلاغك: " },
  },
};

Deno.serve(async (req) => {
  try {
    const expectedSecret = Deno.env.get("ORDER_NOTIFY_SECRET");
    const saB64 = Deno.env.get("FIREBASE_SA_B64");
    if (!expectedSecret || !saB64) return json({ error: "NOT_CONFIGURED" }, 503);
    if (req.headers.get("x-notify-secret") !== expectedSecret) {
      return json({ error: "UNAUTHORIZED" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const reportId = body.report_id;
    const event = `${body.event ?? ""}`;
    if (!reportId || !(event in COPY)) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: report } = await admin
      .from("customer_reports")
      .select("id, user_id, subject")
      .eq("id", reportId)
      .maybeSingle();

    if (!report) return json({ sent: 0, reason: "REPORT_NOT_FOUND" });

    let targets: string[];
    if (event === "new_report") {
      const { data: admins } = await admin
        .from("profiles")
        .select("id")
        .eq("role", "admin");
      targets = (admins ?? []).map((a) => `${a.id}`);
    } else {
      targets = report.user_id ? [`${report.user_id}`] : [];
    }
    if (targets.length === 0) return json({ sent: 0, reason: "NO_RECIPIENT" });

    const { data: profiles } = await admin
      .from("profiles")
      .select("id, fcm_token, locale")
      .in("id", targets)
      .not("fcm_token", "is", null);

    const recipients = profiles ?? [];
    if (recipients.length === 0) return json({ sent: 0, reason: "NO_TOKEN" });

    const subject = `${report.subject ?? ""}`.slice(0, 80);
    const sa = JSON.parse(atob(saB64));
    const authClient = new JWT({
      email: sa.client_email,
      key: sa.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const { token: accessToken } = await authClient.getAccessToken();

    let sent = 0;
    const stale: string[] = [];

    await Promise.all(recipients.map(async (recipient) => {
      const lang: Lang = recipient.locale === "ar" ? "ar" : "en";
      const copy = COPY[event][lang];
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
              token: recipient.fcm_token,
              notification: { title: copy.title, body: `${copy.body}${subject}` },
              data: { report_id: `${reportId}`, event },
            },
          }),
        },
      );

      if (fcmRes.ok) {
        sent += 1;
        return;
      }
      const detail = await fcmRes.text();
      console.error("FCM send failed", fcmRes.status, detail);
      if (fcmRes.status === 404 || fcmRes.status === 410) {
        stale.push(`${recipient.id}`);
      }
    }));

    if (stale.length > 0) {
      await admin.from("profiles").update({ fcm_token: null }).in("id", stale);
    }

    console.log("pushed", event, reportId, "->", sent, "of", recipients.length);
    return json({ sent });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
