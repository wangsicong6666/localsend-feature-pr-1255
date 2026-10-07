import 'dart:io';

import 'package:common/common.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/provider/chat/chat_database.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('Chat');
const _uuid = Uuid();

final chatProvider = NotifierProvider<ChatNotifier, ChatViewState>((ref) {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<ChatViewState> {
  ChatDatabase? _db;
  Future<void>? _opening;

  @override
  ChatViewState init() => ChatViewState.empty;

  Future<void> ensureReady() async {
    if (_db != null) {
      return;
    }
    final pending = _opening;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _open();
    _opening = future;
    try {
      await future;
    } catch (_) {
      if (identical(_opening, future)) {
        _opening = null;
      }
      rethrow;
    }
  }

  Future<void> _open() async {
    final support = await getApplicationSupportDirectory();
    final db = ChatDatabase.open(
      databasePath: p.join(support.path, 'chat.sqlite'),
      mediaRoot: p.join(support.path, 'chat_media'),
    );
    _db = db;
    final active = db.activeFingerprint();
    state = ChatViewState(
      conversations: db.listConversations(),
      activeFingerprint: active,
      messages: active == null ? const [] : db.messagesFor(active),
      pending: state.pending,
      bubbleMaxHeight: db.bubbleMaxHeight(),
      composerHeight: db.composerHeight(),
      ready: true,
    );
  }

  Future<ChatDatabase> _database() async {
    await ensureReady();
    return _db!;
  }

  void _reload() {
    final db = _db;
    if (db == null) {
      return;
    }
    final active = state.activeFingerprint;
    state = state.copyWith(
      conversations: db.listConversations(),
      messages: active == null ? const [] : db.messagesFor(active),
      ready: true,
    );
  }

  Future<void> openConversation({
    required String fingerprint,
    required String alias,
    required String ip,
    required int port,
    required bool https,
  }) async {
    final db = await _database();
    final key = chatPeerKey(fingerprint, ip);
    db.upsertConversation(
      fingerprint: key,
      alias: alias,
      ip: ip,
      port: port,
      https: https,
    );
    db.setActiveFingerprint(key);
    state = state.copyWith(activeFingerprint: key);
    _reload();
  }

  Future<void> setBubbleMaxHeight(double height) async {
    final clamped = height.clamp(80.0, 480.0);
    final db = await _database();
    db.setBubbleMaxHeight(clamped);
    state = state.copyWith(bubbleMaxHeight: clamped);
  }

  Future<void> setComposerHeight(double height) async {
    final clamped = height.clamp(72.0, 320.0);
    final db = await _database();
    db.setComposerHeight(clamped);
    state = state.copyWith(composerHeight: clamped);
  }

  Future<int> addPaths(List<String> paths) async {
    await ensureReady();
    var skippedDirs = 0;
    final next = [...state.pending];
    for (final path in paths) {
      if (path.isEmpty) {
        continue;
      }
      if (Directory(path).existsSync() || chatIsDirectoryName(path)) {
        skippedDirs++;
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final name = p.basename(path);
      next.add(PendingAttachment(
        id: _uuid.v4(),
        name: name,
        fileType: name.guessFileType(),
        size: file.lengthSync(),
        path: path,
        bytes: null,
      ));
    }
    state = state.copyWith(pending: next);
    return skippedDirs;
  }

  Future<void> addImageBytes(List<int> bytes, {String? fileName}) async {
    await ensureReady();
    final name = fileName ?? 'clipboard.png';
    state = state.copyWith(
      pending: [
        ...state.pending,
        PendingAttachment(
          id: _uuid.v4(),
          name: name,
          fileType: FileType.image,
          size: bytes.length,
          path: null,
          bytes: bytes,
        ),
      ],
    );
  }

  void removePending(String id) {
    state = state.copyWith(
      pending: state.pending.where((item) => item.id != id).toList(),
    );
  }

  void clearPending() {
    state = state.copyWith(pending: const []);
  }

  Future<void> recordOutgoingSession(SendSessionState session) async {
    final db = await _database();
    final target = session.target;
    final peer = chatPeerKey(target.fingerprint, target.ip);
    db.upsertConversation(
      fingerprint: peer,
      alias: target.alias,
      ip: target.ip,
      port: target.port,
      https: target.https,
    );

    final files = session.files.values.toList();
    final textOnly = files.length == 1 && files.first.file.fileType == FileType.text && (files.first.file.preview?.isNotEmpty ?? false);
    if (textOnly) {
      db.insertMessage(
        id: session.sessionId,
        peerFingerprint: peer,
        direction: ChatDirection.outgoing,
        text: files.first.file.preview,
        createdAt: db.nextCreatedAt(),
        status: ChatPartStatus.sending,
        parts: const [],
      );
      _reload();
      return;
    }

    final parts = <ChatPart>[];
    var index = 0;
    for (final file in files) {
      if (chatIsDirectoryName(file.file.fileName)) {
        continue;
      }
      String? openPath = file.path;
      if (file.file.fileType == FileType.image) {
        openPath = await db.copyImage(
          peerKey: peer,
          partId: file.file.id,
          sourcePath: file.path,
          bytes: file.bytes,
        );
      }
      parts.add(ChatPart(
        id: file.file.id,
        messageId: session.sessionId,
        fileName: file.file.fileName,
        fileType: file.file.fileType,
        fileSize: file.file.size,
        openPath: openPath,
        status: ChatPartStatus.sending,
        sortIndex: index++,
      ));
    }
    if (parts.isEmpty) {
      return;
    }
    db.insertMessage(
      id: session.sessionId,
      peerFingerprint: peer,
      direction: ChatDirection.outgoing,
      text: null,
      createdAt: db.nextCreatedAt(),
      status: ChatPartStatus.sending,
      parts: parts,
    );
    _reload();
  }

  Future<void> syncOutgoingSession(SendSessionState session) async {
    final db = await _database();
    final files = session.files.values.toList();
    final textOnly = files.length == 1 && files.first.file.fileType == FileType.text && (files.first.file.preview?.isNotEmpty ?? false);
    if (textOnly) {
      db.setMessageStatus(session.sessionId, _sessionStatus(session.status));
      _reload();
      return;
    }

    var changed = false;
    for (final file in files) {
      if (!db.hasPart(file.file.id)) {
        continue;
      }
      final partStatus = _fileStatus(file.status, session.status);
      if (partStatus == ChatPartStatus.sending) {
        continue;
      }
      db.updatePart(partId: file.file.id, status: partStatus, keepPath: true);
      changed = true;
    }
    if (changed || _isTerminal(session.status)) {
      _reload();
    }
  }

  Future<void> recordIncomingText({
    required String fingerprint,
    required String ip,
    required int port,
    required bool https,
    required String alias,
    required String messageId,
    required String text,
  }) async {
    final db = await _database();
    final peer = chatPeerKey(fingerprint, ip);
    final createdAt = db.nextCreatedAt();
    db.upsertConversation(
      fingerprint: peer,
      alias: alias,
      ip: ip,
      port: port,
      https: https,
      updatedAt: createdAt,
    );
    db.insertMessage(
      id: messageId,
      peerFingerprint: peer,
      direction: ChatDirection.incoming,
      text: text,
      createdAt: createdAt,
      status: ChatPartStatus.finished,
      parts: const [],
    );
    db.setActiveFingerprint(peer);
    state = state.copyWith(activeFingerprint: peer);
    _reload();
  }

  Future<void> recordIncomingFiles({
    required String fingerprint,
    required String ip,
    required int port,
    required bool https,
    required String alias,
    required String messageId,
    required List<({String id, String fileName, FileType fileType, int size})> files,
  }) async {
    final chatFiles = files.where((f) => !chatIsDirectoryName(f.fileName)).toList();
    if (chatFiles.isEmpty) {
      return;
    }
    final db = await _database();
    final peer = chatPeerKey(fingerprint, ip);
    final createdAt = db.nextCreatedAt();
    db.upsertConversation(
      fingerprint: peer,
      alias: alias,
      ip: ip,
      port: port,
      https: https,
      updatedAt: createdAt,
    );
    db.insertMessage(
      id: messageId,
      peerFingerprint: peer,
      direction: ChatDirection.incoming,
      text: null,
      createdAt: createdAt,
      status: ChatPartStatus.sending,
      parts: [
        for (var i = 0; i < chatFiles.length; i++)
          ChatPart(
            id: chatFiles[i].id,
            messageId: messageId,
            fileName: chatFiles[i].fileName,
            fileType: chatFiles[i].fileType,
            fileSize: chatFiles[i].size,
            openPath: null,
            status: ChatPartStatus.sending,
            sortIndex: i,
          ),
      ],
    );
    _reload();
  }

  Future<void> finishIncomingPart({
    required String partId,
    required bool success,
    required FileType fileType,
    String? savedPath,
  }) async {
    final db = await _database();
    if (!db.hasPart(partId)) {
      return;
    }
    if (!success) {
      db.updatePart(partId: partId, status: ChatPartStatus.failed, openPath: null);
      _reload();
      return;
    }
    var openPath = savedPath;
    if (fileType == FileType.image && savedPath != null) {
      final peer = db.peerForPart(partId);
      if (peer != null) {
        openPath = await db.copyImage(peerKey: peer, partId: partId, sourcePath: savedPath) ?? savedPath;
      }
    }
    db.updatePart(partId: partId, status: ChatPartStatus.finished, openPath: openPath);
    _reload();
  }
}

ChatPartStatus _fileStatus(FileStatus fileStatus, SessionStatus sessionStatus) {
  switch (fileStatus) {
    case FileStatus.finished:
      return ChatPartStatus.finished;
    case FileStatus.failed:
    case FileStatus.skipped:
      return ChatPartStatus.failed;
    case FileStatus.queue:
    case FileStatus.sending:
      if (_isTerminal(sessionStatus) && sessionStatus != SessionStatus.finished && sessionStatus != SessionStatus.finishedWithErrors) {
        return ChatPartStatus.failed;
      }
      if (sessionStatus == SessionStatus.finishedWithErrors && fileStatus != FileStatus.finished) {
        return fileStatus == FileStatus.queue ? ChatPartStatus.failed : ChatPartStatus.sending;
      }
      return ChatPartStatus.sending;
  }
}

ChatPartStatus _sessionStatus(SessionStatus status) {
  switch (status) {
    case SessionStatus.finished:
      return ChatPartStatus.finished;
    case SessionStatus.waiting:
    case SessionStatus.sending:
      return ChatPartStatus.sending;
    case SessionStatus.recipientBusy:
    case SessionStatus.declined:
    case SessionStatus.finishedWithErrors:
    case SessionStatus.canceledBySender:
    case SessionStatus.canceledByReceiver:
      return ChatPartStatus.failed;
  }
}

bool _isTerminal(SessionStatus status) {
  switch (status) {
    case SessionStatus.waiting:
    case SessionStatus.sending:
      return false;
    case SessionStatus.recipientBusy:
    case SessionStatus.declined:
    case SessionStatus.finished:
    case SessionStatus.finishedWithErrors:
    case SessionStatus.canceledBySender:
    case SessionStatus.canceledByReceiver:
      return true;
  }
}

void logChatError(Object error, StackTrace stackTrace) {
  _logger.warning('Chat history update failed', error, stackTrace);
}
