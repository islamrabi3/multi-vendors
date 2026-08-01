import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/models/support.dart';
import '../../core/repositories/support_repository.dart';
import '../../core/services/attachment_service.dart';
import '../../core/widgets/chat_attachment_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/skeleton.dart' show ButtonSpinner;
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// One support conversation.
///
/// The same screen serves the user and the admin — only [asAdmin] changes,
/// which decides bubble alignment and which side the message is stamped as.
/// A second widget tree for "the same chat, mirrored" would drift.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    required this.thread,
    this.asAdmin = false,
  });

  final SupportThread thread;
  final bool asAdmin;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _repo = SupportRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<List<SupportMessage>> _stream =
      _repo.messagesStream(widget.thread.id);

  /// The thread row itself is streamed too, so resolving on one side updates
  /// the other immediately instead of on the next time the screen is opened.
  late final Stream<SupportThread?> _threadStream =
      _repo.threadStream(widget.thread.id);

  /// Only the customer is offered templates — an admin is the one they exist
  /// to stand in for.
  late final Future<List<SupportTemplate>> _templates =
      widget.asAdmin ? Future.value(const []) : _repo.fetchTemplates();

  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({ChatAttachment? attachment}) async {
    final text = _input.text.trim();
    if ((text.isEmpty && attachment == null) || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.send(
        threadId: widget.thread.id,
        message: text,
        fromAdmin: widget.asAdmin,
        attachment: attachment,
      );
      _input.clear();
      // A user reply reopens the thread server-side; the thread stream carries
      // that back, so nothing is mirrored locally.
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// One tap posts the reason and the platform's standard answer together.
  ///
  /// "Something else" is the same call — it simply has no canned reply on the
  /// server, so the thread lands in the admin queue instead, which is the
  /// "I want to talk to a person" path.
  Future<void> _sendTemplate(SupportTemplate template) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _repo.sendTemplate(
        threadId: widget.thread.id,
        key: template.key,
        languageCode: Localizations.localeOf(context).languageCode,
      );
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    // Held busy across the picker and the upload both: the send button is the
    // only spinner on the screen, and an upload with no sign of progress reads
    // as nothing having happened.
    setState(() => _sending = true);
    ChatAttachment? attachment;
    try {
      attachment = await pickChatAttachment(context);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (attachment == null || !mounted) return;
    await _send(attachment: attachment);
  }

  Future<void> _toggleResolved(String current) async {
    try {
      await _repo.setStatus(
          widget.thread.id, current == 'open' ? 'resolved' : 'open');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(widget.asAdmin
            ? (widget.thread.userName ?? l10n.customer)
            : l10n.supportChat),
        actions: [
          if (widget.asAdmin)
            StreamBuilder<SupportThread?>(
              stream: _threadStream,
              builder: (context, snap) {
                final status = snap.data?.status ?? widget.thread.status;
                return TextButton(
                  onPressed: () => _toggleResolved(status),
                  child: Text(
                      status == 'open' ? l10n.markResolved : l10n.reopen),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Visible to the user as well: a thread the platform considers done
          // should say so on both sides, the moment it happens.
          StreamBuilder<SupportThread?>(
            stream: _threadStream,
            builder: (context, snap) {
              final status = snap.data?.status ?? widget.thread.status;
              if (status != 'resolved') return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg, vertical: AppSpace.md),
                color: AppColors.successFill,
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 17, color: AppColors.successInk),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        l10n.supportResolvedNotice,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.successInk),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<SupportMessage>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return FailureView(error: snap.error!);
                }
                final messages = snap.data ?? const <SupportMessage>[];
                if (messages.isEmpty) {
                  // An empty thread is the one moment a menu of reasons is
                  // more useful than a blank box: most of them are answered
                  // by a template, and the customer never waits for an agent.
                  if (widget.asAdmin) {
                    return EmptyView(
                      message: l10n.supportChatEmpty,
                      icon: Icons.support_agent_outlined,
                    );
                  }
                  return _TemplatePicker(
                    templates: _templates,
                    busy: _sending,
                    onPick: _sendTemplate,
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: messages[i],
                    // Mine when the sender's side matches the side I am on.
                    mine: messages[i].isFromAdmin == widget.asAdmin,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                    top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.attachSomething,
                    onPressed: _sending ? null : _attach,
                    icon: const Icon(Icons.attach_file_rounded, size: 21),
                    color: AppColors.textMuted,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: l10n.typeAMessage,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.lg, vertical: AppSpace.md),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      onPressed: _sending ? null : () => _send(),
                      child: _sending
                          ? const ButtonSpinner(size: 16)
                          : const Icon(Icons.send_rounded, size: 19),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the customer sees instead of an empty thread.
class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({
    required this.templates,
    required this.busy,
    required this.onPick,
  });

  final Future<List<SupportTemplate>> templates;
  final bool busy;
  final void Function(SupportTemplate) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return FutureBuilder<List<SupportTemplate>>(
      future: templates,
      builder: (context, snap) {
        final items = snap.data ?? const <SupportTemplate>[];
        // No templates configured, or they could not be read: the thread still
        // works as a plain conversation, so this falls back rather than
        // blocking the screen on them.
        if (items.isEmpty) {
          return EmptyView(
            message: l10n.supportChatEmpty,
            icon: Icons.support_agent_outlined,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            const SizedBox(height: AppSpace.xl),
            Icon(Icons.support_agent_outlined,
                size: 44, color: AppColors.textFaint),
            const SizedBox(height: AppSpace.lg),
            Text(
              l10n.howCanWeHelp,
              textAlign: TextAlign.center,
              style: AppType.heading(18),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.pickTopicOrWrite,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            for (final template in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: OutlinedButton(
                  onPressed: busy ? null : () => onPick(template),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    alignment: AlignmentDirectional.centerStart,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        template.hasReply
                            ? Icons.bolt_rounded
                            : Icons.forum_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text(template.label(language))),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final SupportMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.md - 2),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.surface,
          border: Border.all(
              color: mine ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadii.lg),
            topRight: const Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(mine ? AppRadii.lg : AppRadii.xs),
            bottomRight: Radius.circular(mine ? AppRadii.xs : AppRadii.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.hasAttachment) ...[
              ChatAttachmentView(
                path: message.attachmentPath!,
                name: message.attachmentName,
                isImage: message.isImageAttachment,
                onDark: mine,
              ),
              if (message.message.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.message.isNotEmpty)
              Text(
                message.message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: mine ? Colors.white : AppColors.ink,
                ),
              ),
            // Says plainly that nobody has read the thread yet, so a customer
            // is not left expecting a person who has not arrived.
            if (message.isAutomated) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.automaticReply,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 3),
            Text(
              DateFormat('h:mm a').format(message.createdAt.toLocal()),
              style: TextStyle(
                fontSize: 10,
                color: mine
                    ? Colors.white.withValues(alpha: 0.75)
                    : AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
