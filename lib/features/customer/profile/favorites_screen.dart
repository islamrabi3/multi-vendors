import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/vendor.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/widgets/common.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _repository = FavoritesRepository();
  List<Vendor>? _vendors;

  @override
  void initState() {
    super.initState();
    _repository.fetchFavoriteVendors().then((vendors) {
      if (mounted) setState(() => _vendors = vendors);
    }).catchError((_) {
      if (mounted) setState(() => _vendors = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _vendors;
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: vendors == null
          ? const LoadingView()
          : vendors.isEmpty
              ? const EmptyView(
                  message: 'No favorites yet', icon: Icons.favorite_outline)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: vendors.length,
                  itemBuilder: (context, index) {
                    final vendor = vendors[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: AppNetworkImage(
                            url: vendor.logoUrl,
                            height: 44,
                            width: 44,
                            borderRadius: BorderRadius.circular(8)),
                        title: Text(vendor.name),
                        subtitle: Text(vendor.isOpen ? 'Open' : 'Closed'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/vendors/${vendor.id}'),
                      ),
                    );
                  },
                ),
    );
  }
}
