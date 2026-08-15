import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

/// One column of a [WebTable] — a label plus how much of the row's width it
/// claims. `flex` mirrors [Expanded]'s meaning; a fixed-width trailing
/// column (a status badge, an amount) usually wants `flex: 0` with an
/// explicit [width] instead.
class WebTableColumn {
  const WebTableColumn({required this.label, this.flex = 1, this.width});

  final String label;
  final int flex;
  final double? width;
}

/// A dense, brand-styled table for genuinely tabular admin/vendor lists —
/// the web-width alternative to a vertical stack of full-width cards.
/// Deliberately hand-built rather than Flutter's `DataTable` (which brings
/// its own Material chrome that fights [AppColors]/[AppRadii]) and without a
/// third-party grid package (nothing this list needs is sortable/pinned).
class WebTable extends StatelessWidget {
  const WebTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyState,
    this.trailingWidth = 20,
  });

  final List<WebTableColumn> columns;
  final List<Widget> rows;
  final Widget? emptyState;

  /// Must match the `trailingWidth` passed to each row — wider than the
  /// default icon-sized slot when rows carry action buttons instead of a
  /// chevron (see [WebTableRow.trailingWidth]).
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.canvas,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
            child: _WebTableRowLayout(
              columns: columns,
              trailingWidth: trailingWidth,
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: emptyState ?? const SizedBox.shrink()),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderSoft,
                ),
              rows[i],
            ],
        ],
      ),
    );
  }
}

/// One row inside a [WebTable]. [cells] must line up 1:1 with the parent
/// table's `columns` (this widget doesn't hold a reference back to them —
/// each cell just needs to be built with the same `flex`/`width` the header
/// used, via [WebTableRow.aligned]).
class WebTableRow extends StatelessWidget {
  const WebTableRow({
    super.key,
    required this.cells,
    this.onTap,
    this.trailing,
    this.trailingWidth = 20,
  });

  /// Builds a row whose cells share the exact flex/width of [columns], so
  /// the header and body always line up without repeating the numbers.
  factory WebTableRow.aligned({
    Key? key,
    required List<WebTableColumn> columns,
    required List<Widget> cells,
    VoidCallback? onTap,
    Widget? trailing,
    double trailingWidth = 20,
  }) {
    assert(columns.length == cells.length);
    return WebTableRow(
      key: key,
      onTap: onTap,
      trailing: trailing,
      trailingWidth: trailingWidth,
      cells: [
        for (var i = 0; i < columns.length; i++)
          _Cell(column: columns[i], child: cells[i]),
      ],
    );
  }

  final List<Widget> cells;
  final VoidCallback? onTap;

  /// A chevron by default when [onTap] is set; pass an explicit widget (a
  /// status badge, an icon button) to replace it.
  final Widget? trailing;

  /// Must match the parent [WebTable.trailingWidth] so the header and every
  /// row's trailing slot line up. Widen this when [trailing] is action
  /// buttons rather than an icon.
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final trailingWidget =
        trailing ??
        (onTap != null
            ? const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textFaint,
              )
            : const SizedBox.shrink());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.canvas,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < cells.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpace.md),
                      cells[i],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              SizedBox(
                width: trailingWidth,
                child: Align(child: trailingWidget),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.column, required this.child});

  final WebTableColumn column;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (column.width != null) {
      return SizedBox(width: column.width, child: child);
    }
    return Expanded(flex: column.flex, child: child);
  }
}

/// Renders just the label row — shared by the header (labels) so its column
/// widths are computed identically to the body's [_Cell]s.
class _WebTableRowLayout extends StatelessWidget {
  const _WebTableRowLayout({
    required this.columns,
    required this.trailingWidth,
  });

  final List<WebTableColumn> columns;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.md),
                _Cell(
                  column: columns[i],
                  child: Text(
                    columns[i].label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpace.md),
        SizedBox(width: trailingWidth),
      ],
    );
  }
}
