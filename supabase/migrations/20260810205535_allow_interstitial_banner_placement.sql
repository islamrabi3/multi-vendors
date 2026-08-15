-- Keep the database allow-list aligned with AdPlacement.interstitial in the
-- client. The original constraint predates full-screen ads and rejects any
-- insert that selects `interstitial`.
alter table public.banners
	drop constraint if exists banners_placement_check;

alter table public.banners
	add constraint banners_placement_check
	check (placement in (
		'home_carousel',
		'home_inline',
		'vendor_top',
		'cart',
		'order_tracking',
		'interstitial'
	));
