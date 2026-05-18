import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'health_graph_service.dart';
import 'inference_service.dart';
import '../models/health_log.dart';

class RetrieverService extends ChangeNotifier {
  final HealthGraphService graphService;
  final InferenceService inferenceService;

  // Scoring weights
  static const double wGraph = 0.30;
  static const double wTemporal = 0.20;
  static const double wSemantic = 0.50;

  // Beam parameters
  static const int beamWidth = 50;
  static const int maxDepth = 5;
  static const double depthDecay = 0.85;

  // Seed finding
  static const int topKPerEntity = 50;

  // Relation weights
  static const Map<String, double> relationWeights = {
    "HAS_SYMPTOM": 1.25,
    "TARGETS": 1.10,
    "TRIGGERED_BY": 1.20,
    "HAS_EVENT": 1.15,
    "PART_OF": 0.80,
  };

  static const Set<String> traversableRelations = {
    "HAS_SYMPTOM",
    "TARGETS",
    "TRIGGERED_BY",
    "HAS_EVENT",
    "PART_OF",
  };

  RetrieverService({
    required this.graphService,
    required this.inferenceService,
  });

  Future<Map<String, dynamic>> retrieveEvidenceBundle(String query, {int limit = 20}) async {
    final now = DateTime.now(); // Standardize to local device time
    
    // 1. Extract Entities
    final queryPlan = await _extractQueryEntities(query);
    
    // Defensive parsing of entities
    List<dynamic> entities = [];
    if (queryPlan['entities'] is List) {
      entities = queryPlan['entities'];
    } else if (queryPlan['entities'] is String) {
      entities = [{"text": queryPlan['entities'], "type": "other"}];
    }
    
    // 2. Phase 1: Seed Finding
    final seeds = await _findSeedNodes(entities);
    
    // 3. Phase 2: Beam Traversal
    List<Map<String, dynamic>> hits = [];
    if (seeds.isNotEmpty) {
      hits = await _beamSearchEvents(seeds, now: now);
    }
    
    List<Map<String, dynamic>> events = [];
    if (hits.isEmpty) {
      events = await _lexicalFallback(query, now);
    } else {
      for (var hit in hits) {
        events.add(await _buildEvidence(hit));
      }
    }
    
    // 4. Phase 3: Semantic Scoring & Reranking
    final queryEmbedding = await inferenceService.getEmbedding(query);
    events = await _scoreSemantic(events, queryEmbedding);
    events = _rerankEvents(events, queryPlan, query);
    
    // 5. Final Top 10 + Temporal Tagging
    final topEvents = events.take(10).toList();
    final localNow = DateTime.now();

    for (var event in topEvents) {
      if (event['event_time'] == null) continue;
      final eTime = DateTime.parse(event['event_time']).toLocal();
      final isToday = eTime.year == localNow.year && eTime.month == localNow.month && eTime.day == localNow.day;
      
      final String tag = isToday ? "(Today's Event)" : "(Past Event)";
      final originalText = event['raw_text'] ?? event['name'] ?? "Unknown event";
      event['raw_text'] = "$originalText $tag";
    }
    
    // 6. Phase 4: Chronic Context
    var background = await _getAlwaysOnC5Events(now, queryEmbedding);
    background.sort((a, b) => (b['query_sim'] as double).compareTo(a['query_sim'] as double));

    return {
      "query": query,
      "query_time": now.toIso8601String(),
      "query_plan": queryPlan,
      "seed_nodes": seeds.take(20).toList(),
      "events": topEvents,
      "background_facts": background,
    };
  }

  Future<Map<String, dynamic>> _extractQueryEntities(String query) async {
    try {
      final response = await inferenceService.extractLogData(query);
      return response;
    } catch (e) {
      // Fallback to simple tokenization if LLM fails
      final tokens = query.toLowerCase().split(RegExp(r'\W+')).where((t) => t.length > 2).toList();
      return {
        "entities": tokens.map((t) => {"text": t, "type": "other"}).toList(),
        "intent": "general",
        "source": "fallback",
      };
    }
  }

  Future<List<Map<String, dynamic>>> _findSeedNodes(List<dynamic> entities) async {
    final db = graphService.db;
    if (db == null) return [];

    final List<Map<String, dynamic>> allNodes = await db.query('nodes');
    final Map<String, Map<String, dynamic>> bestByNode = {};

    for (var entity in entities) {
      final entityText = entity['text'] as String;
      final qEmb = await inferenceService.getEmbedding(entityText);
      
      List<Map<String, dynamic>> scored = [];
      for (var node in allNodes) {
        double score = 0.0;
        
        // Pass 1: Embedding similarity
        if (node['embedding_json'] != null && qEmb != null) {
          final decoded = json.decode(node['embedding_json']);
          if (decoded is List) {
            final nodeEmb = decoded.cast<double>().toList();
            score = _cosineSimilarity(qEmb, nodeEmb);
          }
        }
        
        // Pass 2: Lexical match (supplement)
        final name = (node['canonical_name'] ?? node['name'] ?? "").toString().toLowerCase();
        final exactMatch = name.contains(entityText.toLowerCase()) || entityText.toLowerCase().contains(name);
        
        if (exactMatch) {
          score = math.max<double>(score, 0.90);
        }
        
        scored.add({
          "node": node,
          "score": score,
        });
      }
      
      scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      
      for (var item in scored.take(topKPerEntity)) {
        final node = item['node'];
        final nodeId = node['node_id'];
        final score = item['score'] as double;
        
        if (bestByNode[nodeId] == null || score > bestByNode[nodeId]!['seed_score']) {
          bestByNode[nodeId] = {
            "node_id": nodeId,
            "name": node['canonical_name'] ?? node['name'],
            "type": node['type'],
            "seed_score": score,
            "matched_entity": entityText,
            "matched_entity_type": entity['type'] ?? 'other',
          };
        }
      }
    }

    final seeds = bestByNode.values.toList();
    seeds.sort((a, b) => (b['seed_score'] as double).compareTo(a['seed_score'] as double));
    return seeds.take(50).toList();
  }

  Future<List<Map<String, dynamic>>> _beamSearchEvents(List<Map<String, dynamic>> seeds, {required DateTime now}) async {
    final db = graphService.db;
    if (db == null) return [];

    List<Map<String, dynamic>> beam = seeds.map((s) => {
      "node_id": s["node_id"],
      "score": s["seed_score"],
      "depth": 0,
      "path": [s],
    }).toList();

    final Map<String, Map<String, dynamic>> eventHits = {};
    final Map<String, double> bestSeen = {};

    for (int d = 0; d <= maxDepth; d++) {
      List<Map<String, dynamic>> nextBeam = [];

      for (var item in beam) {
        final nodeId = item["node_id"];
        final node = (await db.query('nodes', where: 'node_id = ?', whereArgs: [nodeId])).firstOrNull;
        if (node == null) continue;

        if (node['type'] == 'event') {
          final relevance = _scoreNodeRelevance(node, now);
          if (!eventHits.containsKey(nodeId)) {
            eventHits[nodeId] = {
              "node": node,
              "graph_score": item["score"],
              "relevance_score": relevance,
              "paths": [item["path"]],
            };
          } else {
            if (item["score"] > eventHits[nodeId]!["graph_score"]) {
              eventHits[nodeId]!["graph_score"] = item["score"];
            }
            if (relevance > eventHits[nodeId]!["relevance_score"]) {
              eventHits[nodeId]!["relevance_score"] = relevance;
            }
            (eventHits[nodeId]!["paths"] as List).add(item["path"]);
          }
        }

        if (item["depth"] >= maxDepth) continue;

        final neighbors = await _getNeighbors(nodeId);
        for (var neighbor in neighbors) {
          final relWeight = relationWeights[neighbor['relation']] ?? 1.0;
          final nextScore = item["score"] * relWeight * depthDecay;
          final neighborId = neighbor["node_id"];

          if (nextScore <= (bestSeen[neighborId] ?? 0.0)) continue;
          bestSeen[neighborId] = nextScore;

          final nRow = (await db.query('nodes', where: 'node_id = ?', whereArgs: [neighborId])).firstOrNull;
          if (nRow == null) continue;

          nextBeam.add({
            "node_id": neighborId,
            "score": nextScore,
            "depth": item["depth"] + 1,
            "path": [...item["path"], {
              "node_id": neighborId,
              "name": nRow["canonical_name"] ?? nRow["name"],
              "type": nRow["type"],
              "relation": neighbor["relation"],
              "direction": neighbor["direction"],
              "score": nextScore,
            }],
          });
        }
      }

      nextBeam.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      beam = nextBeam.take(beamWidth).toList();
      if (beam.isEmpty) break;
    }

    return eventHits.values.toList();
  }

  Future<List<Map<String, dynamic>>> _getNeighbors(String nodeId) async {
    final db = graphService.db;
    if (db == null) return [];

    final List<Map<String, dynamic>> edges = await db.query(
      'edges',
      where: '(source_id = ? OR target_id = ?) AND relation IN (${traversableRelations.map((e) => "'$e'").join(',')})',
      whereArgs: [nodeId, nodeId],
    );

    return edges.map((edge) {
      final isSource = edge['source_id'] == nodeId;
      return {
        "node_id": isSource ? edge['target_id'] : edge['source_id'],
        "relation": edge['relation'],
        "direction": isSource ? "out" : "in",
      };
    }).toList();
  }

  double _scoreNodeRelevance(Map<String, dynamic> node, DateTime now) {
    final impactClass = node['impact_class'] ?? "C1";
    final s0 = (node['S0'] ?? 0.5).toDouble();
    final lambdaHr = (node['lambda_hr'] ?? 0.0).toDouble();
    final isCyclic = (node['is_cyclic'] ?? 0) == 1;
    final cyclicPeriod = (node['cyclic_period_hrs'] as num?)?.toDouble();
    final occurrenceCount = (node['occurrence_count'] ?? 1).toInt();

    if (node['event_time'] == null) return 0.0;
    final eventTime = DateTime.parse(node['event_time']).toUtc();

    if (impactClass == "C5") return s0;

    final hoursSince = now.difference(eventTime).inSeconds / 3600.0;
    
    if (isCyclic && cyclicPeriod != null && cyclicPeriod > 0) {
      final tSinceInCycle = hoursSince % cyclicPeriod;
      final tUntil = cyclicPeriod - tSinceInCycle;
      final tProx = math.min<double>(tSinceInCycle, tUntil);
      return s0 * math.exp(-lambdaHr * tProx);
    }

    final boost = math.min<double>(1.0 + (occurrenceCount - 1) * 0.25, 2.0);
    return s0 * boost * math.exp(-lambdaHr * math.max<double>(hoursSince, 0.0));
  }

  Future<Map<String, dynamic>> _buildEvidence(Map<String, dynamic> hit) async {
    final node = hit['node'];
    final nodeId = node['node_id'];
    
    // Get context states
    final db = graphService.db;
    final List<Map<String, dynamic>> edges = await db!.query(
      'edges',
      where: "source_id = ? AND relation IN ('HAS_SYMPTOM', 'TARGETS', 'TRIGGERED_BY')",
      whereArgs: [nodeId],
    );
    
    List<Map<String, dynamic>> states = [];
    for (var edge in edges) {
      final target = (await db.query('nodes', where: 'node_id = ?', whereArgs: [edge['target_id']])).firstOrNull;
      if (target != null) {
        states.add({
          "relation": edge['relation'],
          "node_id": target['node_id'],
          "name": target['canonical_name'] ?? target['name'],
        });
      }
    }

    final metadata = node['metadata_json'] != null ? json.decode(node['metadata_json']) : {};

    return {
      "event_id": nodeId,
      "name": node["canonical_name"] ?? node["name"],
      "raw_text": metadata["raw_text"],
      "event_type": node["event_type"] ?? metadata["event_type"],
      "event_time": node["event_time"] ?? metadata["event_time"],
      "impact_class": node["impact_class"] ?? metadata["impact_class"],
      "relevance_score": hit["relevance_score"],
      "graph_score": hit["graph_score"],
      "query_sim": 0.0,
      "score": 0.0,
      "states": states,
      "paths": hit["paths"],
    };
  }

  Future<List<Map<String, dynamic>>> _scoreSemantic(List<Map<String, dynamic>> events, List<double>? queryEmbedding) async {
    if (queryEmbedding == null) return events;

    for (var event in events) {
      final rawText = event['raw_text'] as String?;
      if (rawText == null || rawText.isEmpty) {
        event['query_sim'] = 0.0;
        continue;
      }
      final eventEmbedding = await inferenceService.getEmbedding(rawText);
      if (eventEmbedding != null) {
        event['query_sim'] = _cosineSimilarity(queryEmbedding, eventEmbedding);
      } else {
        event['query_sim'] = 0.0;
      }
    }
    return events;
  }

  List<Map<String, dynamic>> _rerankEvents(List<Map<String, dynamic>> events, Map<String, dynamic> queryPlan, String query) {
    for (var event in events) {
      final g = math.min<double>((event['graph_score'] ?? 0.0).toDouble(), 1.5);
      final t = math.min<double>((event['relevance_score'] ?? 0.0).toDouble(), 1.0);
      final s = (event['query_sim'] ?? 0.0).toDouble();
      
      final isC5 = event['impact_class'] == "C5";
      final c5Bonus = isC5 ? (0.10 + s * 0.15) : 0.0;

      event['score'] = (s * wSemantic) + (t * wTemporal) + (g * wGraph) + c5Bonus;
    }

    events.sort((a, b) => ((b['score'] ?? 0.0) as num).toDouble().compareTo(((a['score'] ?? 0.0) as num).toDouble()));
    return events.where((e) => ((e['score'] ?? 0.0) as num).toDouble() >= 0.10).toList();
  }

  Future<List<Map<String, dynamic>>> _getAlwaysOnC5Events(DateTime now, List<double>? queryEmbedding) async {
    final db = graphService.db;
    if (db == null) return [];

    final List<Map<String, dynamic>> c5Nodes = await db.query(
      'nodes',
      where: "type = 'event' AND impact_class = 'C5'",
    );

    List<Map<String, dynamic>> results = [];
    for (var node in c5Nodes) {
      final relevance = _scoreNodeRelevance(node, now);
      double querySim = 0.0;
      
      final metadata = node['metadata_json'] != null ? json.decode(node['metadata_json']) : {};
      final rawText = metadata['raw_text'] as String?;
      
      if (queryEmbedding != null && rawText != null && rawText.isNotEmpty) {
        final emb = await inferenceService.getEmbedding(rawText);
        if (emb != null) {
          querySim = _cosineSimilarity(queryEmbedding, emb);
        }
      }

      results.add({
        "node": node,
        "graph_score": querySim,
        "relevance_score": relevance,
        "query_sim": querySim,
        "paths": [],
      });
    }

    List<Map<String, dynamic>> evidenceList = [];
    for (var res in results) {
      evidenceList.add(await _buildEvidence(res)..['query_sim'] = res['query_sim']);
    }
    return evidenceList;
  }

  Future<List<Map<String, dynamic>>> _lexicalFallback(String query, DateTime now) async {
    final db = graphService.db;
    if (db == null) return [];
    
    final tokens = query.toLowerCase().split(RegExp(r'\W+')).where((t) => t.length > 2).toSet();
    final List<Map<String, dynamic>> allEvents = await db.query('nodes', where: "type = 'event'");
    
    List<Map<String, dynamic>> results = [];
    for (var event in allEvents) {
      final metadata = event['metadata_json'] != null ? json.decode(event['metadata_json']) : {};
      final rawText = (metadata['raw_text'] ?? "").toString().toLowerCase();
      final eventTokens = rawText.split(RegExp(r'\W+')).toSet();
      
      final intersection = tokens.intersection(eventTokens);
      if (intersection.isNotEmpty) {
        final relevance = _scoreNodeRelevance(event, now);
        results.add(await _buildEvidence({
          "node": event,
          "graph_score": intersection.length.toDouble(),
          "relevance_score": relevance,
          "paths": [],
        }));
      }
    }
    
    results.sort((a, b) => (b['graph_score'] as double).compareTo(a['graph_score'] as double));
    return results;
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
