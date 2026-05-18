import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'health_graph_service.dart';
import 'inference_service.dart';

class HealthProfileService extends ChangeNotifier {
  final HealthGraphService graphService;
  final InferenceService inferenceService;

  HealthProfileService({
    required this.graphService,
    required this.inferenceService,
  });

  Future<String> generateProfile() async {
    final db = graphService.db;
    if (db == null) return "Database not initialized.";

    // 1. Gather all event nodes
    final List<Map<String, dynamic>> allEvents = await db.query(
      'nodes', 
      where: "type = 'event'", 
      orderBy: 'datetime(event_time) DESC'
    );

    if (allEvents.isEmpty) {
      return "No health data recorded yet. Start logging symptoms or activities to generate your Health Profile.";
    }

    // 2. Filter for Chronic Baseline (C5)
    final chronic = allEvents.where((e) => e['impact_class'] == 'C5').toList();

    // 3. Gather Active Concerns (C3, C4, C6) - Last 20 events
    final active = allEvents
        .where((e) => ['C3', 'C4', 'C6'].contains(e['impact_class']))
        .take(20)
        .toList();

    // 4. Gather Recent Anomalies (Last 14 days, C1, C2)
    final lookback = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final recent = allEvents
        .where((e) => e['event_time'] != null && e['event_time'].toString().compareTo(lookback) >= 0)
        .where((e) => ['C1', 'C2'].contains(e['impact_class']))
        .take(15)
        .toList();

    // 5. Get Episodes
    final allEpisodes = await graphService.getNodesByType('episode');
    final episodes = allEpisodes.where((e) => e['name'] != 'none_episode').toList();

    // 6. Build Payload
    final payload = {
      "chronic_conditions": chronic.map((e) => _summarizeEvent(e)).toList(),
      "active_concerns": active.map((e) => _summarizeEvent(e)).toList(),
      "recent_anomalies": recent.map((e) => _summarizeEvent(e)).toList(),
      "episodes": episodes.take(10).map((e) {
        final Map<String, dynamic> ep = Map<String, dynamic>.from(e);
        if (ep['metadata_json'] != null) {
          try {
            ep['metadata'] = json.decode(ep['metadata_json']);
          } catch (_) {}
        }
        return ep;
      }).toList(),
    };

    // 7. Call Dedicated Clinical LLM
    return await inferenceService.generateClinicalSummary(payload);
  }

  Map<String, dynamic> _summarizeEvent(Map<String, dynamic> event) {
    final metadata = event['metadata_json'] != null ? json.decode(event['metadata_json']) : {};
    return {
      "text": metadata['raw_text'] ?? event['name'],
      "date": event['event_time']?.toString().substring(0, 10),
      "type": event['event_type'] ?? metadata['event_type'],
      "impact": event['impact_class'],
      "severity": event['severity_band'],
    };
  }
}
