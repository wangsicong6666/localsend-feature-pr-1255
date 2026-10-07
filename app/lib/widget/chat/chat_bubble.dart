import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:refena_flutter/refena_flutter.dart';

int _halfDayKey(int millis) {
  final local = DateTime.fromMillisecondsSinceEpoch(millis);
  final afternoon = local.hour >= 12 ? 1 : 0;
  return local.year * 100000 + local.month * 1000 + local.day * 10 + afternoon;
}

String formatChatTimestamp(int millis) {
  final local = DateTime.fromMillisecondsSinceEpoch(millis);
  final locale = LocaleSettings.currentLocale.languageTag;
  final period = local.hour < 12 ? t.chat.morning : t.chat.afternoon;
  return '${DateFormat.yMd(locale).format(local)} $period';
}

bool chatNeedsDateHeader(ChatMessage? previous, ChatMessage current) {
  if (previous == null) {
    return true;
  }
  return _halfDayKey(previous.createdAt) != _halfDayKey(current.createdAt);
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final double maxTextHeight;

  const ChatBubble({
    required this.message,
    required this.maxTextHeight,
  });

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == ChatDirection.outgoing;
    final maxWidth = math.max(220.0, MediaQuery.sizeOf(context).width * 0.42);
    final background = outgoing ? const Color(0xFF1A6B45) : Theme.of(context).colorScheme.surfaceVariant;
    final foreground = outgoing ? Colors.white : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.text != null && message.text!.isNotEmpty)
                  _BubbleText(
                    text: message.text!,
                    maxHeight: maxTextHeight,
                    style: TextStyle(color: foreground, fontSize: 15, height: 1.3),
                    showCopy: true,
                  ),
                if (message.images.isNotEmpty) ...[
                  if (message.text != null && message.text!.isNotEmpty) const SizedBox(height: 8),
                  _ImageGrid(images: message.images),
                ],
                if (message.files.isNotEmpty) ...[
                  if ((message.text != null && message.text!.isNotEmpty) || message.images.isNotEmpty) const SizedBox(height: 8),
                  for (final file in message.files) _FileRow(messageId: message.id, part: file, foreground: foreground),
                ],
                if (message.status == ChatPartStatus.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(t.chat.failed, style: TextStyle(color: outgoing ? Colors.white70 : Theme.of(context).colorScheme.error, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleText extends StatefulWidget {
  final String text;
  final double maxHeight;
  final TextStyle style;
  final bool showCopy;

  const _BubbleText({
    required this.text,
    required this.maxHeight,
    required this.style,
    required this.showCopy,
  });

  @override
  State<_BubbleText> createState() => _BubbleTextState();
}

class _BubbleTextState extends State<_BubbleText> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) {
      return;
    }
    if (checkPlatformIsDesktop()) {
      context.showSnackBar(t.general.copiedToClipboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final copyWidth = widget.showCopy ? 28.0 : 0.0;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
        )..layout(maxWidth: math.max(0, constraints.maxWidth - copyWidth));
        final tooTall = painter.height > widget.maxHeight;
        painter.dispose();
        final text = Text(widget.text, style: widget.style);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: tooTall
                  ? SizedBox(
                      height: widget.maxHeight,
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          child: text,
                        ),
                      ),
                    )
                  : text,
            ),
            if (widget.showCopy)
              IconButton(
                tooltip: t.general.copy,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  unawaited(_copy());
                },
                icon: Icon(Icons.copy, size: 16, color: widget.style.color),
              ),
          ],
        );
      },
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<ChatPart> images;

  const _ImageGrid({
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    final count = images.length;
    final cross = count == 1 ? 1 : (count == 2 || count == 4 ? 2 : 3);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final part = images[index];
        return _ImageTile(part: part);
      },
    );
  }
}

class _ImageTile extends StatelessWidget {
  final ChatPart part;

  const _ImageTile({
    required this.part,
  });

  @override
  Widget build(BuildContext context) {
    final path = part.openPath;
    final file = path == null ? null : File(path);
    final showImage = file != null && file.existsSync();
    return GestureDetector(
      onDoubleTap: part.canOpen
          ? () async {
              await openFile(context, FileType.image, part.openPath!);
            }
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: Colors.black26,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showImage && file != null)
                Image.file(file, fit: BoxFit.cover, cacheWidth: 480)
              else
                Icon(Icons.image, color: Theme.of(context).colorScheme.outline),
              Positioned(
                top: 2,
                right: 2,
                child: _ImageCopyButton(path: showImage ? path : null),
              ),
              if (part.status == ChatPartStatus.sending)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _imageCopyRadius = 6.0;

class _ImageCopyButton extends StatelessWidget {
  final String? path;

  const _ImageCopyButton({
    required this.path,
  });

  Future<void> _copy(BuildContext context) async {
    final filePath = path;
    if (filePath == null) {
      return;
    }
    final bytes = await File(filePath).readAsBytes();
    await Pasteboard.writeImage(bytes);
    if (!context.mounted) {
      return;
    }
    if (checkPlatformIsDesktop()) {
      context.showSnackBar(t.general.copiedToClipboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = path != null;
    return Tooltip(
      message: t.general.copy,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(_imageCopyRadius),
        child: InkWell(
          onTap: enabled
              ? () {
                  unawaited(_copy(context));
                }
              : null,
          borderRadius: BorderRadius.circular(_imageCopyRadius),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.copy, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final String messageId;
  final ChatPart part;
  final Color foreground;

  const _FileRow({
    required this.messageId,
    required this.part,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    if (part.status == ChatPartStatus.sending) {
      ref.watch(progressProvider);
    }
    final progress = part.status == ChatPartStatus.sending ? ref.notifier(progressProvider).getProgress(sessionId: messageId, fileId: part.id) : 0.0;
    final subtitle = part.status == ChatPartStatus.sending
        ? t.chat.sending
        : part.status == ChatPartStatus.failed
            ? t.chat.failed
            : part.fileSize.asReadableFileSize;

    return InkWell(
      onTap: part.canOpen
          ? () async {
              await openFile(context, part.fileType, part.openPath!);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(part.fileType.icon, color: foreground, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(part.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: foreground, fontSize: 14)),
                  Text(subtitle, style: TextStyle(color: foreground.withOpacity(0.7), fontSize: 12)),
                  if (part.status == ChatPartStatus.sending)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 3),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
