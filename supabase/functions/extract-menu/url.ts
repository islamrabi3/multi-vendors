// Fetching a menu from a link the caller typed.
//
// The server making a request to an address somebody else chose is the whole
// of SSRF: without a check, "https://…" could be swapped for a link to the
// cloud metadata endpoint or to something only reachable from inside the
// network, and the reply would be handed back as if it were a menu. So the
// destination is checked before the first request and again at every redirect
// hop, because a public host is free to redirect to a private one.
//
// This cannot defend against DNS rebinding — the edge runtime does not let us
// pin the resolved address — so the rule is deliberately strict about what a
// menu link may look like rather than clever about what it may resolve to.

const BLOCKED_HOSTS = new Set([
  "localhost",
  "localhost.localdomain",
  "metadata.google.internal",
  "metadata",
  "instance-data",
]);

/// Ranges that are not on the public internet: loopback, link-local (which is
/// where the cloud metadata service lives), and the three private blocks.
function isPrivateIPv4(host: string): boolean {
  const parts = host.split(".");
  if (parts.length !== 4) return false;
  const octets = parts.map((p) => Number(p));
  if (octets.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
  const [a, b] = octets;
  if (a === 0 || a === 127) return true;
  if (a === 10) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a >= 224) return true;
  return false;
}

function isPrivateIPv6(host: string): boolean {
  const address = host.replace(/^\[|\]$/g, "").toLowerCase();
  if (!address.includes(":")) return false;
  if (address === "::1" || address === "::") return true;
  // Unique-local and link-local.
  return /^f[cd]/.test(address) || /^fe[89ab]/.test(address);
}

export class UrlRejected extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

/// Throws unless this is a link the server may fetch on someone's behalf.
export function assertFetchable(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw new UrlRejected("INVALID_URL");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new UrlRejected("INVALID_URL");
  }
  const host = url.hostname.toLowerCase();
  if (BLOCKED_HOSTS.has(host)) throw new UrlRejected("URL_NOT_ALLOWED");
  if (host.endsWith(".local") || host.endsWith(".internal")) {
    throw new UrlRejected("URL_NOT_ALLOWED");
  }
  if (isPrivateIPv4(host) || isPrivateIPv6(host)) {
    throw new UrlRejected("URL_NOT_ALLOWED");
  }
  // A bare name with no dot is something on the local network, not a menu.
  if (!host.includes(".")) throw new UrlRejected("URL_NOT_ALLOWED");
  return url;
}

const MAX_REDIRECTS = 4;
/// How many of a page's own scripts are worth reading before giving up.
const MAX_SCRIPTS = 5;
const MAX_BYTES = 4 * 1024 * 1024;
const TIMEOUT_MS = 20000;

export type Fetched = {
  contentType: string;
  bytes: Uint8Array;
  finalUrl: string;
};

/// Follows redirects by hand so each hop can be checked, and stops reading
/// once the response is larger than a menu could reasonably be.
export async function fetchDocument(start: URL): Promise<Fetched> {
  let url = start;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(url, {
        redirect: "manual",
        signal: controller.signal,
        headers: {
          // Some sites serve a stub to clients that look automated; this is a
          // plain browser string, not an attempt to hide what we are.
          "User-Agent":
            "Mozilla/5.0 (compatible; MenuImporter/1.0; +https://multi-rest-app.web.app)",
          Accept: "text/html,application/xhtml+xml,application/pdf,image/*",
          "Accept-Language": "ar,en;q=0.8",
        },
      });
    } catch {
      throw new UrlRejected("URL_FETCH_FAILED");
    } finally {
      clearTimeout(timer);
    }

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      if (!location) throw new UrlRejected("URL_FETCH_FAILED");
      // Checked again: the hop that matters is the one we are about to make.
      url = assertFetchable(new URL(location, url).toString());
      continue;
    }
    if (!response.ok) throw new UrlRejected("URL_FETCH_FAILED");

    const declared = Number(response.headers.get("content-length") ?? "0");
    if (declared > MAX_BYTES) throw new UrlRejected("URL_TOO_LARGE");

    const buffer = await response.arrayBuffer();
    if (buffer.byteLength > MAX_BYTES) throw new UrlRejected("URL_TOO_LARGE");

    return {
      contentType: (response.headers.get("content-type") ?? "")
        .split(";")[0]
        .trim()
        .toLowerCase(),
      bytes: new Uint8Array(buffer),
      finalUrl: url.toString(),
    };
  }
  throw new UrlRejected("URL_FETCH_FAILED");
}

const MAX_TEXT = 60000;

/// HTML down to the words a menu is made of.
///
/// Script and style bodies go first — they are the bulk of a modern page and
/// none of it is menu — then tags, then the whitespace that is left behind.
/// Truncated at the end, because a menu that runs past 60k characters of text
/// is past what one model call should be asked to read anyway.
export function htmlToText(html: string): string {
  const text = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    // Block ends become line breaks so prices stay with their dish instead of
    // running into the next one.
    .replace(/<\/(p|div|li|tr|h[1-6]|section|article)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/[ \t ]+/g, " ")
    .replace(/\n\s*\n\s*\n+/g, "\n\n")
    .trim();
  return text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) : text;
}

/// Below this, a page has not really said anything.
const MIN_TEXT = 400;

/// The scripts a page loads from its own origin, in the order it loads them.
///
/// Only same-origin: a menu is served by the store's own site, and following
/// a third-party script would fetch analytics and ad code by the megabyte.
function sameOriginScripts(html: string, pageUrl: string): string[] {
  const base = new URL(pageUrl);
  const found: string[] = [];
  const patterns = [
    /<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']/gi,
    /<link\b[^>]*\brel\s*=\s*["']modulepreload["'][^>]*\bhref\s*=\s*["']([^"']+)["']/gi,
  ];
  for (const pattern of patterns) {
    for (const match of html.matchAll(pattern)) {
      try {
        const url = new URL(match[1], base);
        if (url.origin !== base.origin) continue;
        const href = url.toString();
        if (!found.includes(href)) found.push(href);
      } catch {
        // A src we cannot resolve is not one we can fetch.
      }
    }
  }
  return found;
}

/// The parts of a script that look like a menu, and nothing else.
///
/// A single-page app ships its menu inside the bundle, next to a few hundred
/// kilobytes of framework that is of no interest. Rather than send all of it,
/// this keeps a window around every place the code names something the way
/// menu data is named — `name:`, `prices:`, `items:` — and then drops the
/// windows that turn out to be framework code after all. What survives is
/// `{name:"...",description:"...",prices:["90","110"]}`, which reads as
/// clearly as a printed menu.
export function menuLikeRegions(source: string): string {
  const keys =
    /(?:\bname\b|\btitle\b|\bprices?\b|\bitems\b|\bdescription\b|\bsubtitles\b|\bcategory\b|\bmenu\b)\s*:/gi;
  const window = 900;
  const spans: Array<[number, number]> = [];
  for (const match of source.matchAll(keys)) {
    const start = Math.max(0, match.index - window);
    const end = Math.min(source.length, match.index + window);
    const last = spans[spans.length - 1];
    if (last && start <= last[1]) {
      last[1] = Math.max(last[1], end);
    } else {
      spans.push([start, end]);
    }
    if (spans.length > 200) break;
  }

  const kept: string[] = [];
  let budget = MAX_TEXT;
  for (const [start, end] of spans) {
    const chunk = source.slice(start, end);
    // Menu text is words, not identifiers: either something outside the Latin
    // alphabet, or a price list. Framework internals match neither.
    const isMenu = /[^\x00-\x7F]/.test(chunk) ||
      /prices?\s*:\s*\[?\s*["']?\d/.test(chunk);
    if (!isMenu) continue;
    const slice = chunk.slice(0, budget);
    kept.push(slice);
    budget -= slice.length;
    if (budget <= 0) break;
  }
  return kept.join("\n...\n");
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/// What the model should be shown for this link: the page's words, the data
/// inside the scripts it loads, or the file itself when the link points
/// straight at a PDF or a photo of a menu.
export async function asModelInput(
  fetched: Fetched,
): Promise<
  | { kind: "text"; text: string }
  | { kind: "script"; text: string }
  | { kind: "file"; data: string; mediaType: string }
> {
  if (fetched.contentType === "application/pdf") {
    return {
      kind: "file",
      data: toBase64(fetched.bytes),
      mediaType: "application/pdf",
    };
  }
  if (fetched.contentType.startsWith("image/")) {
    return {
      kind: "file",
      data: toBase64(fetched.bytes),
      mediaType: fetched.contentType,
    };
  }
  const html = new TextDecoder("utf-8", { fatal: false }).decode(fetched.bytes);
  const isHtml = fetched.contentType === "text/html" || html.includes("<");
  const text = isHtml ? htmlToText(html) : html.slice(0, MAX_TEXT);
  if (text.trim().length >= MIN_TEXT) return { kind: "text", text };

  // Nothing worth reading in the HTML. Increasingly that is not an empty page
  // but a single-page app: the server sends `<div id="root"></div>` and the
  // menu arrives when the browser runs the JavaScript. We cannot run it, but
  // the menu is usually sitting in the bundle as data, so the bundle is read
  // instead.
  if (isHtml) {
    const scripts = sameOriginScripts(html, fetched.finalUrl).slice(
      0,
      MAX_SCRIPTS,
    );
    const regions: string[] = [];
    let budget = MAX_TEXT;
    for (const script of scripts) {
      if (budget <= 0) break;
      let bundle: Fetched;
      try {
        bundle = await fetchDocument(assertFetchable(script));
      } catch {
        continue; // One unreadable bundle is not the end of the attempt.
      }
      const found = menuLikeRegions(
        new TextDecoder("utf-8", { fatal: false }).decode(bundle.bytes),
      ).slice(0, budget);
      if (found.length === 0) continue;
      regions.push(found);
      budget -= found.length;
    }
    if (regions.length > 0) {
      return { kind: "script", text: regions.join("\n...\n") };
    }
    // The page builds itself in the browser and keeps its menu somewhere we
    // cannot reach — an API call, most likely. Worth its own answer, because
    // "no readable text" would send the operator back to check a link that is
    // perfectly correct.
    throw new UrlRejected("URL_NEEDS_JS");
  }

  if (text.trim().length < 40) throw new UrlRejected("URL_NO_CONTENT");
  return { kind: "text", text };
}
