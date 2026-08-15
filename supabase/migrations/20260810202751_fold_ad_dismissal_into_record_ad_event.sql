-- `record_ad_event` already existed and does exactly this job. The previous
-- migration added `track_ad_event` alongside it, which would have left two
-- functions counting the same thing and a coin-toss over which one a caller
-- used. The new one goes; the old one gains the third event.
drop function if exists public.track_ad_event(uuid, text);

create or replace function public.record_ad_event(p_ad_id uuid, p_event text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if p_event = 'impression' then
    update public.banners set impressions = impressions + 1 where id = p_ad_id;
  elsif p_event = 'click' then
    update public.banners set clicks = clicks + 1 where id = p_ad_id;
  -- Closing an interstitial is a real signal: a high dismissal rate against a
  -- low click rate is how you spot an ad that is only annoying people.
  elsif p_event = 'dismissal' then
    update public.banners set dismissals = dismissals + 1 where id = p_ad_id;
  else
    raise exception 'INVALID_EVENT';
  end if;
end;
$$;

-- An interstitial can be shown before sign-in, so anon must be able to report.
grant execute on function public.record_ad_event(uuid, text) to authenticated, anon;
