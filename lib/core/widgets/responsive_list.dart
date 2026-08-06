import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// A card list that becomes a grid when there is room for one.
///
/// The admin and vendor consoles are used on laptops, where a single column of
/// cards inside a 1200px shell wastes most of the window and turns a
/// twenty-row list into a scroll. The same list, the same cards — laid out in
/// as many columns as fit.
///
/// [itemExtent] is the natural width of one card, not a column count: a fixed
/// count either crushes cards on a small laptop or strands them on a wide
/// monitor.
///
/// One trade-off worth knowing: the multi-column layout builds every item
/// rather than lazily, because a `GridView` would force each row to the
/// tallest card in it and these cards vary. That is fine for a paged list —
/// which is what every caller is — and would not be for an unbounded one.
class ResponsiveCardList extends StatelessWidget {
  const ResponsiveCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.itemExtent = 420,
    this.spacing = AppSpace.sm,
    this.header,
    this.footer,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsets padding;

  /// Roughly how wide one card wants to be. Columns are derived from it.
  final double itemExtent;
  final double spacing;

  /// Pinned above and below the items, full width in both layouts — a filter
  /// bar or a paging footer belongs to the list, not to a column of it.
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding.horizontal;
        // Never fewer than one, and never so many that cards become chips.
        final columns = (available / itemExtent).floor().clamp(1, 4);

        if (columns == 1) {
          return ListView.separated(
            controller: controller,
            padding: padding,
            itemCount:
                itemCount + (header != null ? 1 : 0) + (footer != null ? 1 : 0),
            separatorBuilder: (_, _) => SizedBox(height: spacing),
            itemBuilder: (context, index) {
              var i = index;
              if (header != null) {
                if (i == 0) return header!;
                i -= 1;
              }
              if (i >= itemCount) return footer ?? const SizedBox.shrink();
              return itemBuilder(context, i);
            },
          );
        }

        // Wrapped in a scroll view rather than a GridView so the cards keep
        // their own heights: a grid would force every card in a row to the
        // tallest, which looks like a bug when one has a long subtitle.
        return SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[header!, SizedBox(height: spacing)],
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var i = 0; i < itemCount; i++)
                    SizedBox(
                      width: (available - spacing * (columns - 1)) / columns,
                      child: itemBuilder(context, i),
                    ),
                ],
              ),
              if (footer != null) ...[SizedBox(height: spacing), footer!],
            ],
          ),
        );
      },
    );
  }
}
