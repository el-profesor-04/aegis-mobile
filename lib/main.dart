import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/main_container.dart';
import 'services/health_graph_service.dart';
import 'services/inference_service.dart';
import 'services/retriever_service.dart';
import 'services/episode_service.dart';
import 'services/dispatcher_service.dart';
import 'services/insight_service.dart';
import 'services/health_profile_service.dart';
import 'services/chat_service.dart';
import 'services/knowledge_service.dart';
import 'services/debug_log_service.dart';
import 'widgets/debug_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final graphService = HealthGraphService();
  await graphService.init();
  
  final inferenceService = InferenceService();
  await inferenceService.init();

  final knowledgeService = KnowledgeService(inferenceService);
  await knowledgeService.init();

  final episodeService = EpisodeService(graphService);
  final retrieverService = RetrieverService(
    graphService: graphService,
    inferenceService: inferenceService,
  );
  
  final chatService = ChatService(graphService);
  await chatService.init();

  final dispatcherService = DispatcherService(
    graphService: graphService,
    inferenceService: inferenceService,
    retrieverService: retrieverService,
    episodeService: episodeService,
    chatService: chatService,
    knowledgeService: knowledgeService,
  );

  final insightService = InsightService(graphService);
  final healthProfileService = HealthProfileService(
    graphService: graphService,
    inferenceService: inferenceService,
  );

  final debugService = DebugLogService();
  await debugService.init(); // Load enabled state
  debugService.log("App Starting...");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: graphService),
        ChangeNotifierProvider.value(value: inferenceService),
        ChangeNotifierProvider.value(value: dispatcherService),
        ChangeNotifierProvider.value(value: insightService),
        ChangeNotifierProvider.value(value: healthProfileService),
        ChangeNotifierProvider.value(value: chatService),
        ChangeNotifierProvider.value(value: debugService),
        Provider.value(value: knowledgeService),
      ],
      child: const AegisApp(),
    ),
  );
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aegis Health',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
          surface: Color(0xFF121212),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => DebugOverlay(child: child!),
      home: const MainContainer(),
    );
  }
}
