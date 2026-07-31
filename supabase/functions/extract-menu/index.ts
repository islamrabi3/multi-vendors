// Reads photos of a restaurant menu with OpenAI vision and returns a
// structured, bilingual menu the app can bulk-import.
//
// Request (authenticated): { images: [{ data: <base64>, media_type: "image/jpeg" }] }
// Response: { categories: [{ name, name_ar, items: [{ name, name_ar,
//             description, description_ar, price }] }] }
//
// Both languages are always filled in: a menu photographed in Arabic still
// needs Latin names for the English UI, and vice versa, so the model
// translates whichever side is missing.
//
// Secrets required: OPENAI_API_KEY
import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_IMAGES = 5;
const MODEL = "gpt-4o-mini";

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
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return json({ error: "EXTRACTION_NOT_CONFIGURED" }, 503);

    // Caller must be signed in; menu extraction is a vendor-facing feature
    // but any authenticated user may only burn their own request quota.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData.user) return json({ error: "UNAUTHORIZED" }, 401);

    const body = await req.json().catch(() => ({}));
    const images = Array.isArray(body.images) ? body.images : [];
    if (images.length === 0) return json({ error: "NO_IMAGES" }, 400);
    if (images.length > MAX_IMAGES) return json({ error: "TOO_MANY_IMAGES" }, 400);

    const content: unknown[] = images.map(
      (img: { data: string; media_type?: string }) => ({
        type: "image_url",
        image_url: {
          url: `data:${img.media_type ?? "image/jpeg"};base64,${img.data}`,
          detail: "high",
        },
      }),
    );
    content.push({
      type: "text",
      text:
        "These are photos of a restaurant/store menu (may be in Arabic, " +
        "English, or both). Extract EVERY item you can read.\n" +
        "Return ONLY a JSON object, exactly this shape:\n" +
        '{"categories":[{"name":"...","name_ar":"...","items":' +
        '[{"name":"...","name_ar":"...","description":"...",' +
        '"description_ar":"...","price":0}]}]}\n' +
        "Rules:\n" +
        "- ALWAYS provide both languages for every name. `name` is the " +
        "English/Latin name, `name_ar` is the Arabic name. If the menu only " +
        "shows one language, translate it into the other yourself; never " +
        "leave either empty.\n" +
        "- For a dish with a well-known transliterated name (e.g. koshari, " +
        "shawarma, molokhia), use that transliteration for `name` and the " +
        "Arabic spelling for `name_ar`.\n" +
        "- descriptions are optional: use \"\" when the menu shows none, and " +
        "translate them the same way when it does.\n" +
        "- price is a plain number in the menu's currency (0 if unreadable).\n" +
        "- Group items under the menu's own section headings; if there are " +
        'no headings, use a single category named "Menu" / "القائمة".',
    });

    const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 8192,
        response_format: { type: "json_object" },
        messages: [{ role: "user", content }],
      }),
    });

    if (!openaiRes.ok) {
      const detail = await openaiRes.text();
      console.error("OpenAI error", openaiRes.status, detail);
      return json({ error: "EXTRACTION_FAILED" }, 502);
    }

    const result = await openaiRes.json();
    const text: string = result.choices?.[0]?.message?.content ?? "";

    let parsed: { categories?: unknown };
    try {
      parsed = JSON.parse(text);
    } catch {
      const start = text.indexOf("{");
      const end = text.lastIndexOf("}");
      if (start < 0 || end <= start) return json({ error: "EXTRACTION_FAILED" }, 502);
      parsed = JSON.parse(text.slice(start, end + 1));
    }

    if (!Array.isArray(parsed.categories)) {
      return json({ error: "EXTRACTION_FAILED" }, 502);
    }
    return json({ categories: parsed.categories });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
