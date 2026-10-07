import 'dart:io';

import 'package:common/common.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Local chat history. One row per message bubble, parts for files inside it.
class ChatDatabase {
  final sqlite.Database _db;
  final String mediaRoot;
  int _lastCreatedAt = 0;

  ChatDatabase._(this._db, this.mediaRoot);

  static ChatDatabase open({required String databasePath, required String mediaRoot}) {
    final file = File(databasePath);
    file.parent.createSync(recursive: true);
    Directory(mediaRoot).createSync(recursive: true);
    final db = sqlite.sqlite3.open(databasePath);
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        fingerprint TEXT PRIMARY KEY,
        alias TEXT NOT NULL,
        last_ip TEXT,
        last_port INTEGER,
        https INTEGER,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        peer_fingerprint TEXT NOT NULL,
        direction TEXT NOT NULL,
        body TEXT,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS parts (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        open_path TEXT,
        status TEXT NOT NULL,
        sort_index INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_messages_peer ON messages(peer_fingerprint, created_at)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_parts_message ON parts(message_id, sort_index)');
    return ChatDatabase._(db, mediaRoot);
  }

  void close() => _db.dispose();

  int nextCreatedAt() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _lastCreatedAt) {
      _lastCreatedAt += 1;
    } else {
      _lastCreatedAt = now;
    }
    return _lastCreatedAt;
  }

  double bubbleMaxHeight() {
    final raw = _meta('bubble_max_height');
    final parsed = raw == null ? null : double.tryParse(raw);
    if (parsed == null || parsed < 40) {
      return 200;
    }
    return parsed;
  }

  void setBubbleMaxHeight(double height) {
    _setMeta('bubble_max_height', height.toString());
  }

  double composerHeight() {
    final raw = _meta('composer_height');
    final parsed = raw == null ? null : double.tryParse(raw);
    if (parsed == null || parsed < 72 || parsed > 320) {
      return 120;
    }
    return parsed;
  }

  void setComposerHeight(double height) {
    _setMeta('composer_height', height.toString());
  }

  String? activeFingerprint() => _meta('active_fingerprint');

  void setActiveFingerprint(String? fingerprint) {
    if (fingerprint == null || fingerprint.isEmpty) {
      _db.execute('DELETE FROM meta WHERE key = ?', ['active_fingerprint']);
      return;
    }
    _setMeta('active_fingerprint', fingerprint);
  }

  void upsertConversation({
    required String fingerprint,
    required String alias,
    required String? ip,
    required int? port,
    required bool? https,
    int? updatedAt,
  }) {
    _db.execute(
      '''
      INSERT INTO conversations (fingerprint, alias, last_ip, last_port, https, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(fingerprint) DO UPDATE SET
        alias = excluded.alias,
        last_ip = excluded.last_ip,
        last_port = excluded.last_port,
        https = excluded.https,
        updated_at = excluded.updated_at
      ''',
      [fingerprint, alias, ip, port, https == null ? null : (https ? 1 : 0), updatedAt ?? DateTime.now().millisecondsSinceEpoch],
    );
  }

  List<ChatConversation> listConversations() {
    final rows = _db.select('''
      SELECT c.fingerprint, c.alias, c.last_ip, c.last_port, c.https
      FROM conversations c
      WHERE EXISTS (SELECT 1 FROM messages m WHERE m.peer_fingerprint = c.fingerprint)
      ORDER BY (SELECT MAX(created_at) FROM messages m WHERE m.peer_fingerprint = c.fingerprint) DESC
    ''');
    return rows.map((row) {
      return ChatConversation(
        fingerprint: row['fingerprint'] as String,
        alias: row['alias'] as String,
        lastIp: row['last_ip'] as String?,
        lastPort: row['last_port'] as int?,
        https: row['https'] == null ? null : (row['https'] as int) != 0,
      );
    }).toList();
  }

  void insertMessage({
    required String id,
    required String peerFingerprint,
    required ChatDirection direction,
    required String? text,
    required int createdAt,
    required ChatPartStatus status,
    required List<ChatPart> parts,
  }) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'INSERT OR REPLACE INTO messages (id, peer_fingerprint, direction, body, created_at, status) VALUES (?, ?, ?, ?, ?, ?)',
        [id, peerFingerprint, direction.name, text, createdAt, status.name],
      );
      _db.execute('DELETE FROM parts WHERE message_id = ?', [id]);
      for (final part in parts) {
        _db.execute(
          '''
          INSERT INTO parts (id, message_id, file_name, file_type, file_size, open_path, status, sort_index)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [part.id, id, part.fileName, part.fileType.name, part.fileSize, part.openPath, part.status.name, part.sortIndex],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updatePart({
    required String partId,
    required ChatPartStatus status,
    String? openPath,
    bool keepPath = false,
  }) {
    if (keepPath) {
      _db.execute('UPDATE parts SET status = ? WHERE id = ?', [status.name, partId]);
    } else {
      _db.execute('UPDATE parts SET status = ?, open_path = ? WHERE id = ?', [status.name, openPath, partId]);
    }
    final messageId = _db.select('SELECT message_id FROM parts WHERE id = ?', [partId]);
    if (messageId.isEmpty) {
      return;
    }
    _refreshMessageStatus(messageId.first['message_id'] as String);
  }

  void setMessageStatus(String messageId, ChatPartStatus status) {
    _db.execute('UPDATE messages SET status = ? WHERE id = ?', [status.name, messageId]);
  }

  bool hasPart(String partId) {
    return _db.select('SELECT 1 FROM parts WHERE id = ?', [partId]).isNotEmpty;
  }

  String? peerForPart(String partId) {
    final rows = _db.select(
      '''
      SELECT m.peer_fingerprint AS fingerprint
      FROM parts p
      JOIN messages m ON m.id = p.message_id
      WHERE p.id = ?
      ''',
      [partId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['fingerprint'] as String?;
  }

  List<ChatMessage> messagesFor(String fingerprint) {
    final messageRows = _db.select(
      'SELECT * FROM messages WHERE peer_fingerprint = ? ORDER BY created_at ASC',
      [fingerprint],
    );
    if (messageRows.isEmpty) {
      return [];
    }
    final partRows = _db.select(
      '''
      SELECT p.* FROM parts p
      JOIN messages m ON m.id = p.message_id
      WHERE m.peer_fingerprint = ?
      ORDER BY p.sort_index ASC
      ''',
      [fingerprint],
    );
    final byMessage = <String, List<ChatPart>>{};
    for (final row in partRows) {
      final messageId = row['message_id'] as String;
      byMessage.putIfAbsent(messageId, () => []).add(_partFromRow(row));
    }
    return messageRows.map((row) {
      final id = row['id'] as String;
      return ChatMessage(
        id: id,
        peerFingerprint: row['peer_fingerprint'] as String,
        direction: ChatDirection.values.byName(row['direction'] as String),
        text: row['body'] as String?,
        createdAt: row['created_at'] as int,
        status: ChatPartStatus.values.byName(row['status'] as String),
        parts: byMessage[id] ?? const [],
      );
    }).toList();
  }

  /// Copies an image into chat_media so the bubble does not depend on the original path.
  Future<String?> copyImage({
    required String peerKey,
    required String partId,
    String? sourcePath,
    List<int>? bytes,
  }) async {
    final safe = peerKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dir = Directory(p.join(mediaRoot, safe));
    await dir.create(recursive: true);
    final ext = _extension(sourcePath);
    final dest = p.join(dir.path, '$partId$ext');
    try {
      if (sourcePath != null && await File(sourcePath).exists()) {
        await File(sourcePath).copy(dest);
        return dest;
      }
      if (bytes != null) {
        await File(dest).writeAsBytes(bytes, flush: true);
        return dest;
      }
    } catch (_) {
      return sourcePath;
    }
    return sourcePath;
  }

  void _refreshMessageStatus(String messageId) {
    final rows = _db.select('SELECT status FROM parts WHERE message_id = ?', [messageId]);
    if (rows.isEmpty) {
      return;
    }
    final statuses = rows.map((row) => ChatPartStatus.values.byName(row['status'] as String)).toList();
    final ChatPartStatus next;
    if (statuses.any((s) => s == ChatPartStatus.sending)) {
      next = ChatPartStatus.sending;
    } else if (statuses.any((s) => s == ChatPartStatus.failed)) {
      next = ChatPartStatus.failed;
    } else {
      next = ChatPartStatus.finished;
    }
    setMessageStatus(messageId, next);
  }

  ChatPart _partFromRow(sqlite.Row row) {
    return ChatPart(
      id: row['id'] as String,
      messageId: row['message_id'] as String,
      fileName: row['file_name'] as String,
      fileType: FileType.values.byName(row['file_type'] as String),
      fileSize: row['file_size'] as int,
      openPath: row['open_path'] as String?,
      status: ChatPartStatus.values.byName(row['status'] as String),
      sortIndex: row['sort_index'] as int,
    );
  }

  String? _meta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  void _setMeta(String key, String value) {
    _db.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  String _extension(String? path) {
    if (path == null || path.isEmpty) {
      return '.img';
    }
    final ext = p.extension(path);
    if (ext.isEmpty || ext.length > 8) {
      return '.img';
    }
    return ext;
  }
}
