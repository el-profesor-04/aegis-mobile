import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'health_graph_service.dart';

class ChatMessage {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? toolOutputs;

  ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolOutputs,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? parsedToolOutputs;
    if (map['tool_outputs_json'] != null) {
      try {
        parsedToolOutputs = json.decode(map['tool_outputs_json']);
      } catch (_) {}
    }

    return ChatMessage(
      id: map['message_id'],
      sessionId: map['session_id'],
      role: map['role'],
      content: map['content'],
      timestamp: DateTime.parse(map['timestamp']),
      toolOutputs: parsedToolOutputs,
    );
  }
}

class ChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });
}

class ChatService extends ChangeNotifier {
  final HealthGraphService _graphService;
  final _uuid = const Uuid();

  ChatService(this._graphService);

  List<ChatSession> _sessions = [];
  List<ChatSession> get sessions => _sessions;

  Future<void> init() async {
    await refreshSessions();
  }

  Future<void> refreshSessions() async {
    final db = _graphService.db;
    if (db == null) return;

    final List<Map<String, dynamic>> maps = await db.query(
      'chat_sessions',
      orderBy: 'updated_at DESC',
    );

    _sessions = maps.map((m) => ChatSession(
      id: m['session_id'],
      title: m['title'] ?? 'New Chat',
      updatedAt: DateTime.parse(m['updated_at']),
    )).toList();
    
    notifyListeners();
  }

  Future<String> createSession({String title = "New Conversation"}) async {
    final db = _graphService.db;
    final id = _uuid.v4();
    final now = DateTime.now().toLocal().toIso8601String();

    await db?.insert('chat_sessions', {
      'session_id': id,
      'title': title,
      'created_at': now,
      'updated_at': now,
    });

    await refreshSessions();
    return id;
  }

  Future<void> addMessage(String sessionId, String role, String content, {Map<String, dynamic>? toolOutputs}) async {
    final db = _graphService.db;
    final id = _uuid.v4();
    final now = DateTime.now().toLocal().toIso8601String();

    await db?.insert('chat_messages', {
      'message_id': id,
      'session_id': sessionId,
      'role': role,
      'content': content,
      'timestamp': now,
      'tool_outputs_json': toolOutputs != null ? json.encode(toolOutputs) : null,
    });

    await db?.update(
      'chat_sessions', 
      {'updated_at': now},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    await refreshSessions();
  }

  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final db = _graphService.db;
    final List<Map<String, dynamic>> maps = await db!.query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((m) => ChatMessage.fromMap(m)).toList();
  }
}
