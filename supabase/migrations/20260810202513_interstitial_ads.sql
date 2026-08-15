-- Full-screen ads.
--
-- Built on `banners` rather than beside it: that table is already the ad
-- manager — schedule, audience, media type, impressions, clicks, and the rule
-- that pulls a store's ad the moment the store shuts. An interstitial is the
-- same record shown differently, so it inherits all of that instead of
-- reimplementing it and drifting.
--
-- NOTE: `placement` is text but is *not* free text — it carries a CHECK
-- allow-list from the ad-manager migration, which this file failed to extend.
-- Saving a full-screen ad therefore failed with `banners_placement_check`
-- until 20260810205535 widened it. Any new placement needs that constraint
-- updated too.

alter table public.banners
  -- What the button says. Null means the whole surface is the tap target and
  -- no button is drawn — right for artwork that carries its own call to
  -- action.
  add column if not exists cta_label text,

  -- A full-screen ad the user cannot leave is a trap, so this defaults to
  -- true. It exists only for the rare interstitial that must be acknowledged
  -- (a service outage, a terms change), and the close control still appears
  -- once `dismiss_after_seconds` has elapsed.
  add column if not exists dismissible boolean not null default true,

  -- Seconds before the close control appears. Zero means immediately, which
  -- is what an advert should use.
  add column if not exists dismiss_after_seconds int not null default 0,

  -- How often one user sees it: 'once' | 'daily' | 'every_session'.
  -- Enforced on the client, because "has this person seen it" is per-install
  -- state and round-tripping it would cost a request on every app open.
  add column if not exists frequency text not null default 'once',

  add column if not exists dismissals bigint not null default 0;

alter table public.banners drop constraint if exists banners_frequency_valid;
alter table public.banners
  add constraint banners_frequency_valid
  check (frequency in ('once', 'daily', 'every_session'));

alter table public.banners drop constraint if exists banners_dismiss_delay_sane;
alter table public.banners
  add constraint banners_dismiss_delay_sane
  check (dismiss_after_seconds between 0 and 15);
