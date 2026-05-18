import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/health_graph_service.dart';
import 'package:intl/intl.dart';

class TodayFeed extends StatelessWidget {
  const TodayFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HealthGraphService>(
      builder: (context, graphService, child) {
        final logs = graphService.todayLogs;

        if (logs.isEmpty) {
          return const Center(
            child: Text('No logs in the last 24 hours.', 
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: logs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final log = logs[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        log.type.toUpperCase(),
                        style: TextStyle(
                          color: _getTypeColor(log.type),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        DateFormat('MMM d, h:mm a').format(log.time.toLocal()),
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    log.text,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'symptom': return Colors.redAccent;
      case 'activity': return Colors.greenAccent;
      case 'food': return Colors.orangeAccent;
      case 'sleep': return Colors.blueAccent;
      case 'mood': return Colors.purpleAccent;
      default: return Colors.white54;
    }
  }
}
