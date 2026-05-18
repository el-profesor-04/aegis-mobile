import 'package:flutter/foundation.dart';
import 'debug_log_service.dart';
import 'health_graph_service.dart';
import 'inference_service.dart';
import 'retriever_service.dart';
import 'episode_service.dart';
import 'chat_service.dart';
import 'knowledge_service.dart';

class DispatcherService extends ChangeNotifier {
  final HealthGraphService graphService;
  final InferenceService inferenceService;
  final RetrieverService retrieverService;
  final EpisodeService episodeService;
  final ChatService chatService;
  final KnowledgeService knowledgeService;

  DispatcherService({
    required this.graphService,
    required this.inferenceService,
    required this.retrieverService,
    required this.episodeService,
    required this.chatService,
    required this.knowledgeService,
  });

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  List<String> _activeTools = [];
  List<String> get activeTools => _activeTools;

  String _lastResponse = "";
  String get lastResponse => _lastResponse;

  String? _lastSessionId;
  String? get lastSessionId => _lastSessionId;

  Future<void> handleInput(String text, {String? sessionId, DateTime? timestamp}) async {
    DebugLogService().log("Dispatcher: handleInput - '$text'");
    _isProcessing = true;
    _activeTools = [];
    _lastResponse = "Thinking...";
    _lastSessionId = null;
    notifyListeners();

    try {
      // 1. Fetch History and Save Current Message if in a session
      List<Map<String, String>> history = [];
      String? currentSessionId = sessionId;

      if (currentSessionId != null) {
        // Save user message immediately so it shows up in UI
        await chatService.addMessage(currentSessionId, 'user', text);
        
        final messages = await chatService.getMessages(currentSessionId);
        // History for AI (excluding the message we just added)
        history = messages.take(messages.length - 1).toList().reversed.take(4).toList().reversed.map((m) => {
          "role": m.role == 'user' ? 'human' : 'ai',
          "content": m.content
        }).toList();
      }

      // 2. ROUTER LLM CALL
      DebugLogService().log("Dispatcher: Calling Router...");
      final route = await inferenceService.routeInput(text, history: history);
      DebugLogService().log("Dispatcher: Router raw response: $route");
      
      // Defensive parsing of tools list
      List<String> tools = [];
      if (route['tools'] is List) {
        tools = List<String>.from(route['tools']);
      } else if (route['tools'] is String) {
        tools = [route['tools']];
      }
      
      final urgency = route['urgency'] ?? 'normal';
      final ingestText = route['ingest_text'] as String? ?? text; // Fallback to original text

      _activeTools = tools;
      DebugLogService().log("Dispatcher: Active Tools: $tools");
      notifyListeners();

      Stream<String> responseStream;
      Map<String, dynamic>? finalToolOutputs;

      if (tools.contains('direct_reply') || tools.isEmpty) {
        // DIRECT REPLY (Conversational)
        responseStream = inferenceService.generateFinalAnswerStream(text, {"urgency": "normal"}, history: history);
      } else {
        // RUN TOOLS IN PARALLEL
        final Map<String, dynamic> toolOutputs = {
          "personal_memories": [],
          "first_aid_content": [],
          "ingested": null,
          "urgency": urgency,
        };
        finalToolOutputs = toolOutputs;

        final List<Future> toolFutures = [];

        if (tools.contains('ingest_data')) {
          DebugLogService().log("Tool: ingest_data - STARTING");
          toolFutures.add(_performIngestion(ingestText, timestamp: timestamp).then((val) {
            toolOutputs['ingested'] = val;
            DebugLogService().log("Tool: ingest_data - COMPLETE");
          }));
        }

        if (tools.contains('health_history')) {
          DebugLogService().log("Tool: health_history - STARTING");
          toolFutures.add(retrieverService.retrieveEvidenceBundle(text).then((bundle) {
            toolOutputs['personal_memories'] = bundle['events'];
            DebugLogService().log("Tool: health_history - COMPLETE, Found ${bundle['events']?.length} events");
          }));
        }

        if (tools.contains('first_aid_search')) {
          DebugLogService().log("Tool: first_aid_search - STARTING");
          toolFutures.add(knowledgeService.searchFirstAid(text).then((results) {
            toolOutputs['first_aid_content'] = results;
            DebugLogService().log("Tool: first_aid_search - COMPLETE, Found ${results.length} articles");
          }));
        }

        // Wait for all selected tools to finish
        if (toolFutures.isNotEmpty) {
          await Future.wait(toolFutures);
        }

        // 3. GENERATE ANSWER (Streaming)
        DebugLogService().log("Dispatcher: Generating Final Answer...");
        responseStream = inferenceService.generateFinalAnswerStream(text, toolOutputs, history: history);
      }

      _lastResponse = "";
      await for (final chunk in responseStream) {
        _lastResponse += chunk;
        notifyListeners(); // Refresh UI for streaming effect
      }

      // 4. Update Chat History
      if (currentSessionId == null) {
        // New session per response from main page (saves both user and assistant)
        currentSessionId = await _saveToHistory(text, _lastResponse, toolOutputs: finalToolOutputs);
        _lastSessionId = currentSessionId;
      } else {
        // Append assistant response to existing session (user msg already saved)
        await chatService.addMessage(currentSessionId, 'assistant', _lastResponse, toolOutputs: finalToolOutputs);
      }

    } catch (e) {
      _lastResponse = "I encountered an error: $e";
      DebugLogService().log("Dispatcher ERROR: $e");
      debugPrint("Dispatcher Error: $e");
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _performIngestion(String text, {DateTime? timestamp}) async {
    // 1. Extract full health data
    DebugLogService().log("Ingest: Extracting data...");
    final data = await inferenceService.extractLogData(text);
    DebugLogService().log("Ingest: Data extraction COMPLETE: ${data['symptom'] ?? 'activity'}");
    
    DebugLogService().log("Ingest: Generating embedding...");
    final embedding = await inferenceService.getEmbedding(text);
    DebugLogService().log("Ingest: Embedding COMPLETE");
    
    // Create a copy of data to add raw_text and custom timestamp
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(data);
    metadata['raw_text'] = text; // The actual text typed by the user
    if (timestamp != null) {
      metadata['event_time'] = timestamp.toLocal().toIso8601String();
    }

    // 2. Defensive parsing of entities
    final String? symptomName = metadata['symptom'];
    final String? triggerName = metadata['trigger'];
    
    List<dynamic> bodyParts = [];
    if (metadata['body_parts'] is List) {
      bodyParts = metadata['body_parts'];
    } else if (metadata['body_parts'] is String) {
      bodyParts = [metadata['body_parts']];
    }

    // 3. Add Symptom/State Node
    String? symptomId;
    if (symptomName != null) {
      DebugLogService().log("Ingest: Resolving symptom node: $symptomName");
      symptomId = await graphService.resolveOrCreateNode(name: symptomName, type: 'state');
    }

    // 4. Resolve Body Parts
    for (var bp in bodyParts) {
      await graphService.resolveOrCreateNode(name: bp.toString(), type: 'state');
    }

    // 5. Add Main Event Node
    DebugLogService().log("Ingest: Adding main event node to graph...");
    final eventId = await graphService.addNode(
      type: 'event',
      name: symptomName ?? 'activity',
      embedding: embedding,
      metadata: metadata,
    );

    // 6. Build Edges
    if (symptomId != null) {
      await graphService.addEdge(eventId, symptomId, 'HAS_SYMPTOM');
    }
    if (triggerName != null) {
      final triggerId = await graphService.resolveOrCreateNode(name: triggerName, type: 'state');
      await graphService.addEdge(eventId, triggerId, 'TRIGGERED_BY');
    }

    // 7. Attach to episode
    DebugLogService().log("Ingest: Attaching to episode...");
    await episodeService.attachToEpisode(eventId, metadata);
    
    DebugLogService().log("Ingest: Transaction SUCCESSFUL");
    return {"status": "logged", "extracted_data": metadata};
  }

  Future<String> _saveToHistory(String userText, String assistantResponse, {Map<String, dynamic>? toolOutputs}) async {
    // User requirement: Create a new chat everytime and name it the log text
    final title = userText.length > 40 ? "${userText.substring(0, 37)}..." : userText;
    final sessionId = await chatService.createSession(title: title);
    await chatService.addMessage(sessionId, 'user', userText);
    await chatService.addMessage(sessionId, 'assistant', assistantResponse, toolOutputs: toolOutputs);
    return sessionId;
  }
}
