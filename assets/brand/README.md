# assets/

## What is here

| File | What it is |
| --- | --- |
| `logo-mark.svg` | The Kitchen IN mark — gradient rounded-square tile, white arch, pistachio dot. |
| `logo-mark-mono.svg` | Same geometry; the tile is `fill="currentColor"`. |
| `logo-mark-bare.svg` | No tile — aubergine arch on transparent, for light backgrounds. |
| `logo-lockup.svg` | Mark + "Kitchen IN" wordmark, horizontal. |
| `splash-animated.svg` | **The animated splash screen**, whole, as one file. |

## The mark

An **arch** — a kitchen doorway, and the shape of the letters **I** and **N** — with a
**pistachio dot** inside it: what waits in the kitchen. Geometry, on a 104 viewBox:

- tile `104×104`, radius `30`
- arch `M32 78 V54 a20 20 0 0 1 40 0 V78`, stroke `9`, no fill, open at the bottom
- dot `cx 52 cy 62 r 6.5`

Rules: the arch **never closes at the top** and is **never filled**. The dot is never a
glyph, an emoji or a photo. Scale the stroke with the tile — do not keep it at 9px on a
24px mark.

## The wordmark is type, not art

**"Kitchen IN"** set in **Cairo 800** at `--display-tracking` (−0.02em), with
**"Kitchen" in `--ink` and "IN" in the pistachio green** — so the accent inside the
arch is also the accent inside the name. One space, both capitalised, never
"KITCHEN IN", never "KitchenIN".

Which green depends on the surface, because the pistachio was drawn to sit on
aubergine: on a dark surface "IN" takes `--on-dark-pistachio` (#C3DE84), and on the
light canvas it takes `--pistachio-ink` (#4C6516) — the pistachio darkened until it
reads as text. Raw `--pistachio` (#9DBE3F) on the canvas is about 2:1 and fails WCAG
AA at any size.

> Deviates from the original delivery, which set "IN" in `--primary` (aubergine);
> `logo-lockup.svg` here carries the green. Changed on request.
`logo-lockup.svg` embeds it as `<text>` and therefore needs Cairo available; for
anything where the font may be missing, use `logo-mark.svg` plus live text, or the
`Logo` component.

## The animated splash

`splash-animated.svg` is a **self-contained animated SVG** — the keyframes live in a
`<style>` block inside the file. Drop it in as an `<img>`, a CSS background, a Flutter
`flutter_svg` asset, or a marketing hero and it behaves identically; there is no screen
code to port. It is 390×780 with `preserveAspectRatio="xMidYMid slice"`, so it fills any
phone aspect without distorting.

| at | what |
| --- | --- |
| 0 ms | the aubergine gradient paints |
| 60 ms | glass tile scales 0.82 → 1 and fades in (560 ms) |
| 420 ms | the arch stroke **draws** — left foot, up, over, down (620 ms) |
| 860 ms | the pistachio dot drops into the arch |
| 900 ms | "Kitchen IN" rises 14 px and fades in |
| 1040 ms | the pistachio rule wipes out from centre |
| 1080 ms | tagline follows |
| 1400 ms | loader fades out; the host's CTAs cross-fade in |

Every step uses `--ease-out` (`cubic-bezier(.215,.61,.355,1)`). Nothing bounces or
overshoots. The two decorative circles drift ~40 px over 18–22 s.
`prefers-reduced-motion: reduce` lands the final frame instantly with no animation.

The host page owns only the two buttons at the bottom — see
`ui_kits/customer_app/SplashScreen.jsx`.

## Provenance

The attached codebase (`multi-vendors/`) contains **no image assets at all**:
`pubspec.yaml`'s `flutter: assets:` block is entirely commented out, there is no
`assets/`, `images/` or `fonts/` directory, every runtime image is a Supabase URL, and
every icon is a Material glyph. Its product ("Eaty") drew a different mark inline in
Dart — an orange tile with a white smile.

**Everything in this folder is new work for Kitchen IN**, drawn from the brief's own
requirement for an identity clear of the incumbents. Nothing here was copied from, or
reconstructed from memory of, any existing brand.

## Photography

There is still no brand photography. Food imagery is vendor-uploaded and arrives as a
URL. Where a photo is missing, paint `--image-placeholder` (#F2E6EA) with an
`--image-placeholder-ink` (#B4A0A9) `restaurant` glyph — reproduce that rather than
substituting stock photos.
