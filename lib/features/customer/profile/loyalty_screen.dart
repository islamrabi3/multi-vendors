import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/loyalty_repository.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final LoyaltyRepository _loyaltyRepo = LoyaltyRepository();
  int _points = 0;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLoyalty();
  }

  Future<void> _loadLoyalty() async {
    setState(() => _isLoading = true);
    final pts = await _loyaltyRepo.getPoints();
    final history = await _loyaltyRepo.getHistory();
    setState(() {
      _points = pts;
      _history = history;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.loyaltyRewards), elevation: 0),
      body: _isLoading
          ? const _LoyaltySkeleton()
          : RefreshIndicator(
              onRefresh: _loadLoyalty,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.purple, Colors.deepPurple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          '$_points ${context.l10n.points}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.earnPointsOnOrders,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.l10n.pointsHistory,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          context.l10n.noLoyaltyPointsYet,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  else
                    ..._history.map((item) {
                      final pts = (item['points_change'] as num?) ?? 0;
                      return ListTile(
                        leading: const Icon(
                          Icons.card_giftcard,
                          color: Colors.purple,
                        ),
                        title: Text(
                          item['action'] as String? ?? 'Order reward',
                        ),
                        trailing: Text(
                          '+$pts ${context.l10n.points}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

/// Loyalty while the balance and history load: the points hero, then rows.
class _LoyaltySkeleton extends StatelessWidget {
  const _LoyaltySkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          const Skeleton.box(height: 168, radius: AppRadii.xl),
          const SizedBox(height: AppSpace.xxl),
          const Skeleton.line(widthFactor: 0.4, height: 18),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < 5; i++) ...[
            Row(
              children: const [
                Skeleton.circle(size: 24),
                SizedBox(width: AppSpace.lg),
                Expanded(child: Skeleton.line(widthFactor: 0.55, height: 14)),
                SizedBox(width: AppSpace.lg),
                Skeleton(width: 64, height: 14),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
          ],
        ],
      ),
    );
  }
}
