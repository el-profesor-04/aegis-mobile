import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/category_grid.dart';
import '../widgets/unified_input.dart';
import '../widgets/today_feed.dart';
import '../services/health_graph_service.dart';
import 'chat_room_screen.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/health_profile_service.dart';
import '../services/insight_service.dart';
import '../services/dispatcher_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isGeneratingProfile = false;
  String? _lastProfile;
  Map<String, List<Map<String, dynamic>>> _insights = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshInsights();
      context.read<HealthGraphService>().addListener(_refreshInsights);
    });
  }

  @override
  void dispose() {
    context.read<HealthGraphService>().removeListener(_refreshInsights);
    super.dispose();
  }

  Future<void> _refreshInsights() async {
    final insights = await context.read<InsightService>().getAllInsights();
    if (mounted) {
      setState(() => _insights = insights);
    }
  }

  void _onGenerateProfile() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Health Profile'),
        content: const Text('Do you want to generate your structured Health Profile for a doctor review?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isGeneratingProfile = true);
              
              try {
                final summary = await context.read<HealthProfileService>().generateProfile();
                if (mounted) {
                  setState(() {
                    _isGeneratingProfile = false;
                    _lastProfile = summary;
                  });
                  _showProfileResult(summary);
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isGeneratingProfile = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to generate profile: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Generate', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showProfileResult(String summary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Health Profile', 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 32),
              MarkdownBody(
                data: summary,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white),
                  h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 2.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aegis Health', 
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _onGenerateProfile,
            icon: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.assignment_ind_rounded),
                if (_isGeneratingProfile)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('What happened?', 
                style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 12),
              const CategoryGrid(),
              const SizedBox(height: 30),
              const UnifiedInput(),
              Consumer<DispatcherService>(
                builder: (context, dispatcher, child) {
                  if (dispatcher.lastResponse.isEmpty && !dispatcher.isProcessing) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(top: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bubble_chart, color: Colors.blueAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(dispatcher.isProcessing ? 'Aegis is thinking...' : 'Aegis', 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        if (dispatcher.isProcessing && dispatcher.activeTools.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: dispatcher.activeTools.map((t) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                              ),
                              child: Text(
                                t.replaceAll('_', ' ').toUpperCase(),
                                style: const TextStyle(fontSize: 9, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                              ),
                            )).toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        MarkdownBody(
                          data: dispatcher.lastResponse,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white),
                            h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 2.0),
                            listBullet: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        if (!dispatcher.isProcessing && dispatcher.lastSessionId != null) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatRoomScreen(
                                      sessionId: dispatcher.lastSessionId!,
                                      title: dispatcher.lastSessionId!, // The session ID is currently the log text
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Colors.blueAccent),
                              label: const Text('Go to Conversation', style: TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12), 
                                  side: const BorderSide(color: Colors.white10),
                                ),
                                backgroundColor: Colors.white.withOpacity(0.03),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              if (_insights['correlations']?.isNotEmpty ?? false) ...[
                const SizedBox(height: 32),
                const Text('Insights', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                ..._insights['correlations']!.map((c) => _buildInsightCard(c)),
              ],
              if (_insights['gaps']?.isNotEmpty ?? false) ...[
                const SizedBox(height: 24),
                ..._insights['gaps']!.map((g) => _buildGapCard(g)),
              ],
              const SizedBox(height: 40),
              const Text('Last 24 Hours', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              const TodayFeed(),
              const SizedBox(height: 100), // Extra space for input bar if anchored
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGapCard(Map<String, dynamic> gap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.help_outline, color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              gap['message'],
              style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.orangeAccent),
            ),
          ),
          TextButton(
            onPressed: () {
              // Implementation to 'confirm' the suggested value
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Confirmed. Updating log...'))
              );
            },
            child: const Text('Yes', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(Map<String, dynamic> insight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.withOpacity(0.1), Colors.purple.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              insight['message'],
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
