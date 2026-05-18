import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'inference_service.dart';

class KnowledgeService {
  final InferenceService inferenceService;
  Database? _db;

  KnowledgeService(this.inferenceService);

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'firstaid.db');

    // Copy from assets if doesn't exist
    if (!await File(path).exists()) {
      ByteData data = await rootBundle.load('assets/firstaid.sqlite3');
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes);
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      _db = await databaseFactoryFfi.openDatabase(path);
    } else {
      _db = await openDatabase(path);
    }
  }

  Future<List<String>> searchFirstAid(String query, {int topK = 3}) async {
    if (_db == null) return [];

    final qEmb = await inferenceService.getEmbedding(query);
    if (qEmb == null) return [];

    final List<Map<String, dynamic>> articles = await _db!.query('articles');
    
    List<Map<String, dynamic>> scored = [];
    for (var art in articles) {
      if (art['title_embedding'] == null) continue;
      
      final artEmb = List<double>.from(json.decode(art['title_embedding']));
      final sim = _cosineSimilarity(qEmb, artEmb);
      
      scored.add({
        "content": art['content'],
        "score": sim,
      });
    }

    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    
    return scored
        .take(topK)
        .map((s) => s['content'] as String)
        .toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }
}
