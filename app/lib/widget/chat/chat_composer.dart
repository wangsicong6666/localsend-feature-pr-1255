import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/common.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/util/determine_image_type.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/app_rounded_button_style.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class ChatComposer extends StatefulWidget {
  final Device? onlineDevice;
  final bool enabled;
  final VoidCallback? onJumpToLatest;

  const ChatComposer({
    required this.onlineDevice,
    required this.enabled,
    required this.onJumpToLatest,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(
    onKey: (node, event) {
      if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !event.isShiftPressed) {
        unawaited(_send());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !widget.enabled || widget.onlineDevice == null) {
      return;
    }
    final text = _controller.text.trim();
    final pending = context.ref.read(chatProvider).pending;
    if (text.isEmpty && pending.isEmpty) {
      return;
    }
    final device = widget.onlineDevice!;
    final send = context.ref.notifier(sendProvider);
    setState(() => _sending = true);
    _controller.clear();
    context.ref.notifier(chatProvider).clearPending();
    try {
      if (text.isNotEmpty) {
        final bytes = utf8.encode(text);
        await send.startSession(
              target: device,
              files: [
                CrossFile(
                  name: '${_uuid.v4()}.txt',
                  fileType: FileType.text,
                  size: bytes.length,
                  thumbnail: null,
                  asset: null,
                  path: null,
                  bytes: bytes,
                ),
              ],
              background: true,
              recordChat: true,
            );
      }
      if (pending.isNotEmpty) {
        await send.startSession(
              target: device,
              files: [
                for (final item in pending)
                  CrossFile(
                    name: item.name,
                    fileType: item.fileType,
                    size: item.size,
                    thumbnail: null,
                    asset: null,
                    path: item.path,
                    bytes: item.bytes,
                  ),
              ],
              background: true,
              recordChat: true,
            );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _attach() async {
    final result = await openFiles();
    if (!mounted || result.isEmpty) {
      return;
    }
    final skipped = await context.ref.notifier(chatProvider).addPaths(result.map((file) => file.path).toList());
    if (skipped > 0 && mounted) {
      context.showSnackBar(t.chat.folderRejected);
    }
  }

  Future<void> _paste() async {
    final files = await Pasteboard.files();
    if (!mounted) {
      return;
    }
    if (files.isNotEmpty) {
      var skipped = 0;
      final paths = <String>[];
      for (final file in files) {
        if (Directory(file).existsSync()) {
          skipped++;
        } else {
          paths.add(file);
        }
      }
      if (paths.isNotEmpty) {
        skipped += await context.ref.notifier(chatProvider).addPaths(paths);
      }
      if (skipped > 0 && mounted) {
        context.showSnackBar(t.chat.folderRejected);
      }
      return;
    }

    final image = await Pasteboard.image;
    if (!mounted) {
      return;
    }
    if (image != null && image.isNotEmpty) {
      final now = DateTime.now();
      final name =
          'clipboard_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.${determineImageType(image)}';
      await context.ref.notifier(chatProvider).addImageBytes(image, fileName: name);
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    var text = data?.text;
    text ??= await Pasteboard.text;
    if (!mounted) {
      return;
    }
    if (text == null || text.isEmpty) {
      context.showSnackBar(t.general.noItemInClipboard);
      return;
    }
    final value = _controller.value;
    final start = value.selection.start >= 0 ? value.selection.start : value.text.length;
    final end = value.selection.end >= 0 ? value.selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.ref.watch(chatProvider.select((s) => s.pending));
    final composerHeight = context.ref.watch(chatProvider.select((s) => s.composerHeight));
    final canSend = widget.enabled && widget.onlineDevice != null && !_sending;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(kAppRoundedButtonRadius);
    final enabled = widget.enabled && widget.onlineDevice != null;
    OutlineInputBorder outline(Color color) {
      return OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color));
    }

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.enabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t.chat.selectDeviceFirst, style: TextStyle(color: scheme.outline, fontSize: 12)),
              )
            else if (widget.onlineDevice == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t.chat.offline, style: TextStyle(color: scheme.outline, fontSize: 12)),
              ),
            if (pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in pending)
                      InputChip(
                        label: Text(item.name, overflow: TextOverflow.ellipsis),
                        onDeleted: () => context.ref.notifier(chatProvider).removePending(item.id),
                      ),
                  ],
                ),
              ),
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
                  unawaited(_paste());
                },
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
                  unawaited(_paste());
                },
              },
              child: SizedBox(
                height: composerHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ComposerIconButton(
                      tooltip: t.chat.scrollToLatest,
                      icon: Icons.keyboard_double_arrow_down,
                      onPressed: widget.onJumpToLatest,
                    ),
                    const SizedBox(width: 6),
                    _ComposerIconButton(
                      tooltip: t.chat.attach,
                      icon: Icons.attach_file,
                      onPressed: widget.enabled ? () => unawaited(_attach()) : null,
                    ),
                    const SizedBox(width: 6),
                    _ComposerIconButton(
                      tooltip: t.chat.paste,
                      icon: Icons.content_paste,
                      onPressed: widget.enabled ? () => unawaited(_paste()) : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        focusNode: _focus,
                        controller: _controller,
                        enabled: enabled,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: t.chat.inputHint,
                          filled: true,
                          fillColor: scheme.surface,
                          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          border: outline(scheme.outline),
                          enabledBorder: outline(scheme.outline),
                          focusedBorder: outline(scheme.primary),
                          disabledBorder: outline(scheme.outline.withOpacity(0.4)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ComposerIconButton(
                      tooltip: t.chat.send,
                      icon: Icons.send,
                      filled: true,
                      onPressed: canSend ? () => unawaited(_send()) : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final background = !enabled
        ? scheme.onSurface.withOpacity(0.08)
        : filled
            ? scheme.primary
            : scheme.secondaryContainer;
    final foreground = !enabled
        ? scheme.outline
        : filled
            ? scheme.onPrimary
            : scheme.onSecondaryContainer;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(kAppRoundedButtonRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: foreground),
          ),
        ),
      ),
    );
  }
}
