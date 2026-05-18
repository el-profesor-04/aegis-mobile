import 'dart:math';
import 'package:flutter/foundation.dart';
import 'health_graph_service.dart';
import '../models/decay_config.dart';

class EpisodeService {
  final HealthGraphService _graphService;
  static const double _simThreshold = 0.80;
  static const double _windowMultiplier = 3.0;

  EpisodeService(this._graphService);

  Future<void> attachToEpisode(String eventId, Map<String, dynamic> data) async {
    final symptom = data['symptom'];
    if (symptom == null) return;

    // 1. Find matching episodes
    final List<Map<String, dynamic>> episodes = await _graphService.getNodesByType('episode');
    
    Map<String, dynamic>? bestMatch;
    double maxSim = -1.0;

    for (var ep in episodes) {
      final sim = await _calculateSimilarity(symptom, ep['canonical_name']);
      if (sim > _simThreshold && sim > maxSim) {
        maxSim = sim;
        bestMatch = ep;
      }
    }

    if (bestMatch != null && _withinWindow(bestMatch, data)) {
      await _joinEpisode(bestMatch['node_id'], eventId);
    } else {
      await _createEpisode(eventId, data);
    }
  }

  Future<double> _calculateSimilarity(String a, String b) async {
    // In a real app, this would use the on-device embedding model
    // For now, simple string equality or Jaccard
    if (a.toLowerCase() == b.toLowerCase()) return 1.0;
    return 0.0; 
  }

  bool _withinWindow(Map<String, dynamic> episode, Map<String, dynamic> event) {
    final impactClass = event['impact_class'] ?? 'C1';
    final config = impactClassConfig[impactClass];
    if (config == null || config.halfLifeHrs == null) return true; // C5

    final lastTime = DateTime.parse(episode['event_time'] ?? episode['created_at']);
    final eventTime = DateTime.parse(event['event_time'] ?? DateTime.now().toIso8601String());
    
    final diffHours = eventTime.difference(lastTime).inHours.abs();
    final windowHours = config.halfLifeHrs! * _windowMultiplier;
    
    return diffHours <= windowHours;
  }

  Future<void> _joinEpisode(String episodeId, String eventId) async {
    await _graphService.addEdge(episodeId, eventId, 'HAS_EVENT');
    // Update episode stats
    // ...
  }

  Future<void> _createEpisode(String eventId, Map<String, dynamic> data) async {
    final epId = await _graphService.addNode(
      type: 'episode',
      name: '${data['symptom']}_episode',
      canonicalName: data['symptom'],
      metadata: {'created_from': eventId},
    );
    await _graphService.addEdge(epId, eventId, 'HAS_EVENT');
  }
}

extension on HealthGraphService {
  Future<List<Map<String, dynamic>>> getNodesByType(String type) async {
    if (db == null) return [];
    return await db!.query('nodes', where: 'type = ?', whereArgs: [type]);
  }
}
