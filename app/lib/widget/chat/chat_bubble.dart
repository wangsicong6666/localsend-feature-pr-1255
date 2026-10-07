import 'dart:io';
import 'dart:math' as math;

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:refena_flutter/refena_flutter.dart';

const _dateGap = Duration(minutes: 5);

String formatChatTimestamp(int millis) {
  final local = DateTime.fromMillisecondsSinceEpoch(millis);
  final locale = LocaleSettings.currentLocale.languageTag;
  return '${DateFormat.yMd(locale).format(local)} ${DateFormat.jm(locale).format(local)}';
}

bool chatNeedsDateHeader(ChatMessage? previous, ChatMessage current) {
  if (previous == null) {
    return true;
  }
  final gap = current.createdAt - previous.createdAt;
  return gap >= _dateGap.inMilliseconds;
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
                  _ClippedText(
                    text: message.text!,
                    maxHeight: maxTextHeight,
                    style: TextStyle(color: foreground, fontSize: 15, height: 1.3),
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

class _ClippedText extends StatelessWidget {
  final String text;
  final double maxHeight;
  final TextStyle style;

  const _ClippedText({
    required this.text,
    required this.maxHeight,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = style.fontSize ?? 15;
    final lineHeight = fontSize * (style.height ?? 1.3);
    final maxLines = (maxHeight / lineHeight).floor().clamp(1, 100000);
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.clip,
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
