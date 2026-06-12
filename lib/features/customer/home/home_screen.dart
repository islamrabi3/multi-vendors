import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'home_cubit.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(CatalogRepository()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          if (state.loading) return const LoadingView();
          if (state.error != null && state.vendors.isEmpty) {
            return ErrorView(
                message: 'Could not load stores.', onRetry: cubit.load);
          }
          return RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search stores…',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: cubit.setSearch,
                  ),
                ),
                if (state.banners.isNotEmpty) _Banners(state: state),
                _CategoryChips(state: state),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Stores',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (state.vendors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: EmptyView(
                        message: 'No stores found',
                        icon: Icons.storefront_outlined),
                  )
                else
                  for (final vendor in state.vendors)
                    _VendorCard(vendor: vendor),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: PageView(
        controller: PageController(viewportFraction: 0.92),
        children: [
          for (final banner in state.banners)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: banner.vendorId == null
                    ? null
                    : () => context.push('/vendors/${banner.vendorId}'),
                child: AppNetworkImage(
                  url: banner.imageUrl,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: state.selectedCategoryId == null,
              onSelected: (_) => cubit.selectCategory(null),
            ),
          ),
          for (final category in state.categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(category.name),
                selected: state.selectedCategoryId == category.id,
                onSelected: (_) => cubit.selectCategory(
                    state.selectedCategoryId == category.id ? null : category.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/vendors/${vendor.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AppNetworkImage(
                      url: vendor.coverUrl,
                      height: 130,
                      width: double.infinity),
                  if (!vendor.isOpen)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: const Text('Closed',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    AppNetworkImage(
                        url: vendor.logoUrl,
                        height: 44,
                        width: 44,
                        borderRadius: BorderRadius.circular(8)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vendor.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            '${vendor.avgPrepMinutes} min · '
                            '${formatMoney(vendor.deliveryFee)} delivery',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 2),
                        Text(vendor.ratingCount == 0
                            ? 'New'
                            : vendor.ratingAvg.toStringAsFixed(1)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
