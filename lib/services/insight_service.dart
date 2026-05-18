import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'health_graph_service.dart';

class InsightService extends ChangeNotifier {
  final HealthGraphService graphService;

  InsightService(this.graphService);

  static const double minCorrelationStrength = 0.4;
  static const int minOccurrences = 2;
  static const int lookbackWindowHours = 48;

  Future<Map<String, List<Map<String, dynamic>>>> getAllInsights({DateTime? now}) async {
    final correlations = await getCorrelations();
    final gaps = await getGaps();
    final cyclicChecks = await getCyclicChecks(now: now);

    return {
      "correlations": correlations,
      "gaps": gaps,
      "cyclic_checks": cyclicChecks,
    };
  }

  Future<List<Map<String, dynamic>>> getCorrelations() async {
    final events = await graphService.getEventNodes();
    final allEpisodes = await graphService.getNodesByType('episode');
    final episodes = allEpisodes.where((e) => e['name'] != 'none_episode').toList();
    
    List<Map<String, dynamic>> results = [];

    for (var episode in episodes) {
      final epId = episode['node_id'];
      final epName = (episode['name'] as String).replaceAll('_episode', '');

      // Get all events for this episode
      final List<Map<String, dynamic>> edges = await graphService.db!.query(
        'edges',
        where: "source_id = ? AND relation = 'HAS_EVENT'",
        whereArgs: [epId],
      );

      if (edges.length < minOccurrences) continue;

      final List<String> eIds = edges.map((e) => e['target_id'] as String).toList();
      final epEvents = events.where((e) => eIds.contains(e['node_id'])).toList();

      Map<String, int> triggerCounts = {};

      for (var sEvent in epEvents) {
        // 1. Direct trigger
        final metadata = sEvent['metadata_json'] != null ? json.decode(sEvent['metadata_json']) : {};
        final directTrigger = metadata['trigger'];
        if (directTrigger != null) {
          final tName = _normalizeTrigger(directTrigger);
          if (tName.isNotEmpty) {
            triggerCounts[tName] = (triggerCounts[tName] ?? 0) + 1;
            continue;
          }
        }

        // 2. Contextual trigger
        final sTime = DateTime.parse(sEvent['event_time'] ?? sEvent['created_at']);
        final windowStart = sTime.subtract(const Duration(hours: lookbackWindowHours));

        final potentialTriggers = events.where((e) {
          final eTime = DateTime.parse(e['event_time'] ?? e['created_at']);
          final eType = e['event_type'];
          final eName = e['name'] as String;
          return ['food', 'activity', 'medication', 'sleep', 'mood'].contains(eType) &&
                 eTime.isAfter(windowStart) &&
                 eTime.isBefore(sTime) &&
                 !eName.toLowerCase().contains(epName.toLowerCase());
        }).toList();

        Set<String> seenInWindow = {};
        for (var tEvent in potentialTriggers) {
          final tMetadata = tEvent['metadata_json'] != null ? json.decode(tEvent['metadata_json']) : {};
          final rawTName = tMetadata['trigger'] ?? tMetadata['symptom'] ?? (tEvent['name'] as String).split(':').last;
          final tName = _normalizeTrigger(rawTName);
          if (tName.isNotEmpty && !seenInWindow.contains(tName)) {
            triggerCounts[tName] = (triggerCounts[tName] ?? 0) + 1;
            seenInWindow.add(tName);
          }
        }
      }

      final totalCount = epEvents.length;
      triggerCounts.forEach((tName, count) {
        final strength = count / totalCount;
        if (strength >= minCorrelationStrength && count >= minOccurrences) {
          results.add({
            "type": "correlation",
            "symptom": epName,
            "trigger": tName,
            "strength": strength,
            "occurrences": count,
            "message": "I've noticed ${ (strength * 100).toInt() }% of your $epName episodes happen after you log $tName.",
          });
        }
      });
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> getGaps() async {
    final events = await graphService.getEventNodes();
    if (events.isEmpty) return [];

    final latestEvent = events.first;
    final eId = latestEvent['node_id'];

    final List<Map<String, dynamic>> edges = await graphService.db!.query(
      'edges',
      where: "target_id = ? AND relation = 'HAS_EVENT'",
      whereArgs: [eId],
    );

    if (edges.isEmpty) return [];

    final epId = edges.first['source_id'];
    
    // Check if this is a 'none_episode' before proceeding
    final epNode = await graphService.db!.query('nodes', where: "node_id = ?", whereArgs: [epId]);
    if (epNode.isNotEmpty && epNode.first['name'] == 'none_episode') return [];

    final List<Map<String, dynamic>> otherEdges = await graphService.db!.query(
      'edges',
      where: "source_id = ? AND relation = 'HAS_EVENT' AND target_id != ?",
      whereArgs: [epId, eId],
    );

    if (otherEdges.isEmpty) return [];

    final otherIds = otherEdges.map((e) => e['target_id'] as String).toList();
    final otherEvents = events.where((e) => otherIds.contains(e['node_id'])).toList();

    List<Map<String, dynamic>> gaps = [];
    final currentMd = latestEvent['metadata_json'] != null ? json.decode(latestEvent['metadata_json']) : {};

    for (var field in ['severity_band', 'laterality']) {
      if (currentMd[field] == null) {
        List<String> prevVals = [];
        for (var e in otherEvents) {
          final md = e['metadata_json'] != null ? json.decode(e['metadata_json']) : {};
          if (md[field] != null) prevVals.add(md[field]);
        }

        if (prevVals.isNotEmpty) {
          final mostCommon = _getMostCommon(prevVals);
          gaps.add({
            "type": "gap",
            "field": field,
            "suggested_value": mostCommon,
            "message": "You logged a ${ latestEvent['name'].toString().split(':').last }, but didn't mention $field. Is it $mostCommon like last time?",
          });
        }
      }
    }

    return gaps;
  }

  Future<List<Map<String, dynamic>>> getCyclicChecks({DateTime? now}) async {
    now ??= DateTime.now();
    final cyclicEvents = await graphService.getCyclicNodes();
    if (cyclicEvents.isEmpty) return [];

    List<Map<String, dynamic>> notifications = [];
    
    // Group by canonical_name manually
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var e in cyclicEvents) {
      final name = e['canonical_name'] as String;
      grouped.putIfAbsent(name, () => []).add(e);
    }

    grouped.forEach((name, instances) {
      final latest = instances.first; // Already sorted by DESC time
      final lastTime = DateTime.parse(latest['event_time'] ?? latest['created_at']);
      final periodHrs = (latest['cyclic_period_hrs'] as num?)?.toDouble();

      if (periodHrs != null && periodHrs > 0) {
        final expectedTime = lastTime.add(Duration(minutes: (periodHrs * 60).toInt()));
        final buffer = Duration(minutes: (periodHrs * 0.2 * 60).toInt());

        if (now!.isAfter(expectedTime.add(buffer))) {
          final activityName = name.split(':').last;
          notifications.add({
            "type": "cyclic_check",
            "activity": activityName,
            "last_seen": latest['event_time'],
            "message": "I haven't heard about your $activityName lately. Did you go this week?",
          });
        }
      }
    });

    return notifications;
  }

  String _normalizeTrigger(String name) {
    name = name.toLowerCase().trim();
    if (RegExp(r'cheese|milk|ice cream|dairy|yogurt|pizza|shake|feta').hasMatch(name)) return "dairy";
    if (RegExp(r'stress|work|deadline|tantrum|busy').hasMatch(name)) return "stress";
    if (RegExp(r'sleep|rough night|crying|stayed up|restless').hasMatch(name)) return "poor sleep";
    if (['bloating', 'headache', 'fatigue', 'pain', 'nausea', 'throb', 'stiffness'].contains(name)) return "";
    return name;
  }

  String _getMostCommon(List<String> list) {
    var counts = <String, int>{};
    for (var v in list) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    var sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}
