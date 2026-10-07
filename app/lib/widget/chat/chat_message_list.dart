import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/widget/chat/chat_bubble.dart';
import 'package:localsend_app/widget/local_send_logo.dart';

class ChatMessageList extends StatefulWidget {
  final String? activeFingerprint;
  final List<ChatMessage> messages;
  final double bubbleMaxHeight;

  const ChatMessageList({
    required this.activeFingerprint,
    required this.messages,
    required this.bubbleMaxHeight,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final _controller = ScrollController();
  var _stickToBottom = true;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _lastCount = widget.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final switched = oldWidget.activeFingerprint != widget.activeFingerprint;
    final grew = widget.messages.length != _lastCount;
    _lastCount = widget.messages.length;
    if (switched || (grew && _stickToBottom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    _stickToBottom = position.maxScrollExtent - position.pixels < 80;
  }

  void _jumpToEnd() {
    if (!_controller.hasClients) {
      return;
    }
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeFingerprint == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Opacity(opacity: 0.5, child: LocalSendLogo(withText: false)),
            const SizedBox(height: 16),
            Text(
              t.chat.empty,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    if (widget.messages.isEmpty) {
      return Center(
        child: Text(
          t.chat.noMessages,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final message = widget.messages[index];
        final previous = index == 0 ? null : widget.messages[index - 1];
        final showDate = chatNeedsDateHeader(previous, message);
        return Column(
          children: [
            if (showDate)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  formatChatTimestamp(message.createdAt),
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                ),
              ),
            ChatBubble(message: message, maxTextHeight: widget.bubbleMaxHeight),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
