import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/health_log.dart';
import '../models/decay_config.dart';

class HealthGraphService extends ChangeNotifier {
  Database? _db;
  Database? get db => _db;
  List<HealthLog> _todayLogs = [];
  final _uuid = const Uuid();

  List<HealthLog> get todayLogs => _todayLogs;

  Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aegis_graph.db');

    _db = await openDatabase(
      path,
      version: 3,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE chat_sessions (
              session_id TEXT PRIMARY KEY,
              title TEXT,
              created_at TEXT,
              updated_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE chat_messages (
              message_id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              timestamp TEXT,
              FOREIGN KEY (session_id) REFERENCES chat_sessions (session_id)
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            ALTER TABLE chat_messages ADD COLUMN tool_outputs_json TEXT;
          ''');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE nodes (
            node_id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            name TEXT,
            canonical_name TEXT,
            embedding_json TEXT,
            metadata_json TEXT,
            created_at TEXT,
            event_type TEXT,
            event_time TEXT,
            impact_class TEXT,
            severity_band TEXT,
            S0 REAL,
            lambda_hr REAL,
            is_cyclic INTEGER,
            cyclic_period_hrs REAL,
            occurrence_count INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE edges (
            edge_id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            target_id TEXT NOT NULL,
            relation TEXT NOT NULL,
            timestamp TEXT,
            metadata_json TEXT,
            UNIQUE(source_id, target_id, relation)
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_sessions (
            session_id TEXT PRIMARY KEY,
            title TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_messages (
            message_id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp TEXT,
            tool_outputs_json TEXT,
            FOREIGN KEY (session_id) REFERENCES chat_sessions (session_id)
          )
        ''');
        await db.execute('CREATE INDEX idx_nodes_type ON nodes(type)');
        await db.execute('CREATE INDEX idx_nodes_canonical ON nodes(canonical_name)');
      },
    );

    await refreshLogs();
  }

  Future<void> refreshLogs() async {
    if (_db == null) return;
    final now = DateTime.now().toLocal();
    final lookback = now.subtract(const Duration(hours: 24)).toIso8601String();
    
    final List<Map<String, dynamic>> maps = await _db!.query(
      'nodes',
      where: 'type = ? AND event_time >= ?',
      whereArgs: ['event', lookback],
      orderBy: 'event_time DESC',
    );

    _todayLogs = maps.map((m) => HealthLog.fromMap(_unpackMetadata(m))).toList();
    notifyListeners();
  }

  Map<String, dynamic> _unpackMetadata(Map<String, dynamic> map) {
    final newMap = Map<String, dynamic>.from(map);
    if (map['metadata_json'] != null) {
      try {
        final metadata = json.decode(map['metadata_json']) as Map<String, dynamic>;
        newMap.addAll(metadata); // Flatten metadata fields (including raw_text)
        newMap['metadata'] = metadata; // Keep the original dict too
      } catch (_) {}
    }
    return newMap;
  }

  Future<String> resolveOrCreateNode({required String name, required String type}) async {
    if (_db == null) return "";
    
    final nameLower = name.toLowerCase().trim();
    final List<Map<String, dynamic>> existing = await _db!.query(
      'nodes',
      where: 'type = ? AND LOWER(name) = ?',
      whereArgs: [type, nameLower],
    );

    if (existing.isNotEmpty) {
      return existing.first['node_id'] as String;
    }

    return await addNode(type: type, name: name);
  }

  Future<String> addNode({
    required String type,
    required String name,
    String? canonicalName,
    List<double>? embedding,
    Map<String, dynamic>? metadata,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toLocal().toIso8601String();
    
    final node = {
      'node_id': id,
      'type': type,
      'name': name,
      'canonical_name': canonicalName ?? name,
      'embedding_json': embedding != null ? json.encode(embedding) : null,
      'metadata_json': metadata != null ? json.encode(metadata) : null,
      'created_at': now,
      'event_type': metadata?['event_type'],
      'event_time': metadata?['event_time'] ?? now,
      'impact_class': metadata?['impact_class'],
      'severity_band': metadata?['severity_band'],
      'S0': metadata?['S0'],
      'lambda_hr': metadata?['lambda_hr'],
      'is_cyclic': (metadata?['is_cyclic'] ?? false) ? 1 : 0,
      'cyclic_period_hrs': metadata?['cyclic_period_hrs'],
      'occurrence_count': metadata?['occurrence_count'] ?? 1,
    };

    await _db?.insert('nodes', node, conflictAlgorithm: ConflictAlgorithm.replace);
    if (type == 'event') await refreshLogs();
    return id;
  }

  Future<void> addEdge(String sourceId, String targetId, String relation, [Map<String, dynamic>? metadata]) async {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    
    await _db?.insert('edges', {
      'edge_id': id,
      'source_id': sourceId,
      'target_id': targetId,
      'relation': relation,
      'timestamp': now,
      'metadata_json': metadata != null ? json.encode(metadata) : null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    
    await refreshLogs();
  }

  Future<List<Map<String, dynamic>>> getRelatedEvents(String nodeId, {int depth = 3}) async {
    if (_db == null) return [];
    
    // Simple BFS for related events in the graph
    List<String> currentLayer = [nodeId];
    Set<String> visited = {nodeId};
    List<String> eventIds = [];

    for (int i = 0; i < depth; i++) {
      if (currentLayer.isEmpty) break;
      
      final placeholders = List.filled(currentLayer.length, '?').join(',');
      final List<Map<String, dynamic>> edges = await _db!.rawQuery('''
        SELECT source_id, target_id FROM edges 
        WHERE source_id IN ($placeholders) OR target_id IN ($placeholders)
      ''', [...currentLayer, ...currentLayer]);

      List<String> nextLayer = [];
      for (var edge in edges) {
        final neighbor = edge['source_id'] == currentLayer.first ? edge['target_id'] : edge['source_id'];
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          nextLayer.add(neighbor);
        }
      }
      currentLayer = nextLayer;
    }

    // Filter visited for 'event' nodes
    final placeholders = List.filled(visited.length, '?').join(',');
    final List<Map<String, dynamic>> nodes = await _db!.rawQuery('''
      SELECT * FROM nodes WHERE node_id IN ($placeholders) AND type = 'event'
    ''', visited.toList());
    
    return nodes;
  }

  Future<List<Map<String, dynamic>>> getNodesByType(String type) async {
    if (_db == null) return [];
    return await _db!.query('nodes', where: 'type = ?', whereArgs: [type]);
  }

  Future<List<Map<String, dynamic>>> getEventNodes() async {
    return await getNodesByType('event');
  }

  Future<List<Map<String, dynamic>>> getCyclicNodes() async {
    if (_db == null) return [];
    return await _db!.query('nodes', where: 'type = ? AND is_cyclic = 1', whereArgs: ['event']);
  }

  Future<Map<String, List<HealthLog>>> getAllEventsGroupedByDate() async {
    if (_db == null) return {};
    
    final List<Map<String, dynamic>> maps = await _db!.query(
      'nodes',
      where: 'type = ?',
      whereArgs: ['event'],
      orderBy: 'datetime(event_time) DESC',
    );

    final logs = maps.map((m) => HealthLog.fromMap(_unpackMetadata(m))).toList();
    
    final Map<String, List<HealthLog>> grouped = {};
    for (var log in logs) {
      // Use YYYY-MM-DD format for grouping
      final dateKey = log.time.toLocal().toIso8601String().split('T')[0];
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(log);
    }
    
    return grouped;
  }
}
