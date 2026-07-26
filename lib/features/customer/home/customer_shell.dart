import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../cart/cart_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final cartCount =
        context.select((CartCubit cubit) => cubit.state.itemCount);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: shell,
      floatingActionButton: cartCount > 0
          ? Container(
              decoration: BoxDecoration(
                boxShadow: AppShadows.primaryGlow,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                onPressed: () => context.push('/cart'),
                icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                label: Text(
                  '$cartCount',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
            currentIndex: shell.currentIndex,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textFaint,
            selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 12, height: 1.5),
            unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 12, height: 1.5),
            onTap: (index) => shell.goBranch(index,
                initialLocation: index == shell.currentIndex),
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: context.l10n.home,
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined),
                activeIcon: Icon(Icons.receipt_long),
                label: context.l10n.orders,
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: context.l10n.profile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
