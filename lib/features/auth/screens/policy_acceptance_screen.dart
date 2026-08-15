import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// The terms a store or a rider has to accept before they can trade.
///
/// Shown by the router whenever the server says a document is outstanding, so
/// it covers both cases with one screen: a partner registering for the first
/// time, and an existing partner meeting a version the operator has since
/// published.
///
/// The accept button stays disabled until the text has actually been scrolled
/// to the end. That is not decoration — an agreement nobody could have read
/// is the first thing challenged when it matters, and the scroll is the
/// cheapest honest evidence that the text was put in front of them.
class PolicyAcceptanceScreen extends StatefulWidget {
  const PolicyAcceptanceScreen({super.key});

  @override
  State<PolicyAcceptanceScreen> createState() => _PolicyAcceptanceScreenState();
}

class _PolicyAcceptanceScreenState extends State<PolicyAcceptanceScreen> {
  final _scroll = ScrollController();
  bool _readToEnd = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_readToEnd) return;
      // A short document may not overflow at all, in which case it is already
      // fully read and waiting for a scroll that can never happen.
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 24) {
        setState(() => _readToEnd = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) {
        setState(() => _readToEnd = true);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final state = context.watch<AuthCubit>().state;
    final policy = state.pendingPolicy;

    // The router only shows this while a policy is outstanding; clearing it is
    // what dismisses the screen, so this frame can arrive with nothing to show.
    if (policy == null) return const SizedBox.shrink();

    final canAccept = _readToEnd && _checked && !state.busy;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      // No back button and no leading: this is a condition of using the
      // account, not a page in a flow.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(policy.title(language)),
        actions: [
          TextButton(
            onPressed: () => context.read<AuthCubit>().signOut(),
            child: Text(l10n.signOut),
          ),
        ],
      ),
      body: BlocListener<AuthCubit, AppAuthState>(
        listenWhen: (previous, current) =>
            previous.error != current.error && current.error != null,
        listener: (context, state) => showFailure(context, state.error!),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Expanded(
                    child: Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpace.xl),
                        child: _PolicyBody(
                          markdown: policy.body(language),
                          version: policy.version,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_readToEnd)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.sm),
                            child: Text(
                              l10n.scrollToReadAll,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        CheckboxListTile(
                          value: _checked,
                          onChanged: _readToEnd
                              ? (v) => setState(() => _checked = v ?? false)
                              : null,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l10n.iAgreeToTerms,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        FilledButton(
                          onPressed: canAccept
                              ? () => context
                                    .read<AuthCubit>()
                                    .acceptPendingPolicy()
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: state.busy
                              ? const ButtonSpinner(size: 18)
                              : Text(l10n.acceptAndContinue),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the subset of Markdown these documents actually use — headings,
/// bold runs, and paragraphs.
///
/// A Markdown package would be a dependency added for two syntaxes, and the
/// text is operator-edited: whatever it contains must render as *something*
/// rather than throwing, which a hand-rolled pass guarantees.
class _PolicyBody extends StatelessWidget {
  const _PolicyBody({required this.markdown, required this.version});

  final String markdown;
  final int version;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];

    for (final rawLine in markdown.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        blocks.add(const SizedBox(height: AppSpace.md));
        continue;
      }
      if (line.startsWith('## ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg, bottom: 6),
            child: Text(line.substring(3).trim(), style: AppType.heading(16)),
          ),
        );
        continue;
      }
      if (line.startsWith('# ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg, bottom: 8),
            child: Text(
              line.substring(2).trim(),
              style: AppType.display(20, color: AppColors.ink),
            ),
          ),
        );
        continue;
      }
      blocks.add(
        Text.rich(
          _inline(line),
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.6,
            color: AppColors.ink,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...blocks,
        const SizedBox(height: AppSpace.xl),
        Text(
          context.l10n.policyVersionLabel(version),
          style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
        ),
      ],
    );
  }

  /// Splits `**bold**` runs out of a paragraph. Unmatched markers are left as
  /// literal text rather than swallowing the rest of the line.
  TextSpan _inline(String line) {
    final spans = <TextSpan>[];
    var rest = line;
    while (true) {
      final open = rest.indexOf('**');
      if (open < 0) break;
      final close = rest.indexOf('**', open + 2);
      if (close < 0) break;
      if (open > 0) spans.add(TextSpan(text: rest.substring(0, open)));
      spans.add(
        TextSpan(
          text: rest.substring(open + 2, close),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
      rest = rest.substring(close + 2);
    }
    if (rest.isNotEmpty) spans.add(TextSpan(text: rest));
    return TextSpan(children: spans);
  }
}
