-- Full-screen ads (splash, interstitial) are for signed-in customers only.
-- The app already checks this, but installed builds that predate the check
-- would keep showing them to drivers, stores and staff; the server now
-- returns nothing for those placements to anyone else.
create or replace function public.active_ads(p_placement text, p_is_new_customer boolean default false)
 returns setof banners
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select *
  from public.banners b
  where b.is_active
    and b.placement = p_placement
    and (b.starts_at is null or b.starts_at <= now())
    and (b.ends_at is null or b.ends_at > now())
    and (
      b.audience = 'all'
      or (b.audience = 'new_customers' and p_is_new_customer)
      or (b.audience = 'returning_customers' and not p_is_new_customer)
    )
    and (
      p_placement not in ('splash', 'interstitial')
      or exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'customer'
      )
    )
    -- A store's ad is pulled the moment the store is closed or suspended;
    -- sending customers to a shut restaurant is worse than showing nothing.
    and (
      b.vendor_id is null
      or exists (
        select 1 from public.vendors v
        where v.id = b.vendor_id
          and v.is_active
          and v.approval_status = 'active'
          and public.is_owner_active(v.owner_id)
      )
    )
  order by b.sort_order, b.created_at desc;
$function$;
