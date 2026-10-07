import 'package:common/common.dart';

/// Stable chat peer key. Prefers the certificate fingerprint.
/// Falls back to IP only when a legacy peer omitted the fingerprint.
String chatPeerKey(String? fingerprint, String ip) {
  final fp = fingerprint?.trim() ?? '';
  if (fp.isNotEmpty) {
    return fp;
  }
  return 'ip:$ip';
}

/// Directory payloads use a slash in the file name. Those stay out of chat.
bool chatIsDirectoryName(String name) {
  return name.contains('/') || name.contains('\\');
}

enum ChatDirection { outgoing, incoming }

enum ChatPartStatus { sending, finished, failed }

class ChatConversation {
  final String fingerprint;
  final String alias;
  final String? lastIp;
  final int? lastPort;
  final bool? https;

  const ChatConversation({
    required this.fingerprint,
    required this.alias,
    required this.lastIp,
    required this.lastPort,
    required this.https,
  });
}

class ChatPart {
  final String id;
  final String messageId;
  final String fileName;
  final FileType fileType;
  final int fileSize;
  final String? openPath;
  final ChatPartStatus status;
  final int sortIndex;

  const ChatPart({
    required this.id,
    required this.messageId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.openPath,
    required this.status,
    required this.sortIndex,
  });

  bool get canOpen => status == ChatPartStatus.finished && openPath != null && openPath!.isNotEmpty;
}

class ChatMessage {
  final String id;
  final String peerFingerprint;
  final ChatDirection direction;
  final String? text;
  final int createdAt;
  final ChatPartStatus status;
  final List<ChatPart> parts;

  const ChatMessage({
    required this.id,
    required this.peerFingerprint,
    required this.direction,
    required this.text,
    required this.createdAt,
    required this.status,
    required this.parts,
  });

  List<ChatPart> get images => parts.where((p) => p.fileType == FileType.image).toList();

  List<ChatPart> get files => parts.where((p) => p.fileType != FileType.image).toList();
}

class PendingAttachment {
  final String id;
  final String name;
  final FileType fileType;
  final int size;
  final String? path;
  final List<int>? bytes;

  const PendingAttachment({
    required this.id,
    required this.name,
    required this.fileType,
    required this.size,
    required this.path,
    required this.bytes,
  });
}

class ChatViewState {
  final List<ChatConversation> conversations;
  final String? activeFingerprint;
  final List<ChatMessage> messages;
  final List<PendingAttachment> pending;
  final double bubbleMaxHeight;
  final bool ready;

  const ChatViewState({
    required this.conversations,
    required this.activeFingerprint,
    required this.messages,
    required this.pending,
    required this.bubbleMaxHeight,
    required this.ready,
  });

  static const empty = ChatViewState(
    conversations: [],
    activeFingerprint: null,
    messages: [],
    pending: [],
    bubbleMaxHeight: 200,
    ready: false,
  );

  ChatViewState copyWith({
    List<ChatConversation>? conversations,
    String? activeFingerprint,
    bool clearActive = false,
    List<ChatMessage>? messages,
    List<PendingAttachment>? pending,
    double? bubbleMaxHeight,
    bool? ready,
  }) {
    return ChatViewState(
      conversations: conversations ?? this.conversations,
      activeFingerprint: clearActive ? null : (activeFingerprint ?? this.activeFingerprint),
      messages: messages ?? this.messages,
      pending: pending ?? this.pending,
      bubbleMaxHeight: bubbleMaxHeight ?? this.bubbleMaxHeight,
      ready: ready ?? this.ready,
    );
  }
}
