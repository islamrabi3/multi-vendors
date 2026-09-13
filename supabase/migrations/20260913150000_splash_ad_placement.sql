-- Adds the "splash" placement so an ad can run once, full screen, right
-- after the branded splash animation and before the app opens onto login or
-- home — the client (SplashScreen + InterstitialAds) already targets this
-- value; only the column's whitelist needs to accept it.
--
-- No change needed to active_ads() or record_ad_event(): neither hard-codes
-- a placement list, both just match against whatever is in this column.
alter table public.banners drop constraint banners_placement_check;
alter table public.banners add constraint banners_placement_check
  check (placement = any (array[
    'home_carousel', 'home_inline', 'vendor_top', 'cart',
    'order_tracking', 'interstitial', 'splash'
  ]));
