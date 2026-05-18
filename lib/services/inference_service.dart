import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_log_service.dart';

class InferenceService extends ChangeNotifier {
  static const _channel = MethodChannel('com.aegis.health/litert');
  
  bool get useLMStudio => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  static const String baseUrl = "http://localhost:1234/v1";

  bool _isModelLoaded = false;
  String? _loadError;
  double _downloadProgress = 0.0;
  String _statusMessage = "";

  bool get isModelLoaded => _isModelLoaded;
  String? get loadError => _loadError;
  double get downloadProgress => _downloadProgress;
  String get statusMessage => _statusMessage;

  final String gemmaUrl = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true";
  final String qwenUrl = "https://storage.googleapis.com/mediapipe-models/text_embedder/bert_embedder/float32/1/bert_embedder.tflite";

  // Dynamic Config State
  String _routerPrompt = defaultRouterPrompt;
  String _generatorPrompt = defaultGeneratorPrompt;
  String _extractorPrompt = defaultExtractorPrompt;
  String _summaryPrompt = defaultSummaryPrompt;
  double _temperature = 0.7;
  int _topK = 40;

  String get routerPrompt => _routerPrompt;
  String get generatorPrompt => _generatorPrompt;
  String get extractorPrompt => _extractorPrompt;
  String get summaryPrompt => _summaryPrompt;
  double get temperature => _temperature;
  int get topK => _topK;

  // ── Default Prompts ────────────────────────────────────────────────────────
  static const String defaultRouterPrompt = """
You are the routing agent for Aegis, a personal health assistant. Your job is to decide which tools to call for the user's message.

You have four tools:

1. health_history
   Search the user's personal health graph for relevant events, patterns, and history.

2. first_aid_search
   Search the Mayo Clinic first aid knowledge base for medical guidance.

3. ingest_data
   Extract and store health data from the user's message into their health graph.

4. direct_reply
   Respond conversationally without calling any other tool.

CRITICAL RULES:
- If the user describes ANY health event (symptom, food, activity, mood), you MUST use ingest_data.
- If a user describes a symptom AND asks a question, use BOTH ingest_data AND health_history.
- direct_reply runs ALONE.

Return ONLY valid JSON:
{
  "reasoning": "one sentence explaining why",
  "tools": ["tool1", "tool2"],
  "urgency": "emergency | normal",
  "ingest_text": "exact text to ingest if ingest_data selected, else null"
}
""";

  static const String defaultGeneratorPrompt = """
You are Aegis, a sharp personal health assistant and clinical detective. Your goal is to synthesize retrieved information into a natural, empathetic, and highly analytical response.

REASONING MANDATE:
- You MUST actively cross-reference the user's current query with their "personal_memories".
- Use the dates and tags (Today's Event / Past Event) to build a logical timeline of their health.

CRITICAL RULES:
1. NO ECHOING TODAY: Do not tell the user what they just logged today.
2. PROACTIVE LINKING: Always look for a 'Why'.
3. FORMATTING: Always use organized Markdown.
4. Max 200 words.
""";

  static const String defaultExtractorPrompt = "Extract health data into JSON: \"{text}\". Return JSON with: event_type, symptom, body_parts, trigger, impact_class, severity_band, entities: [{text, type}].";

  static const String defaultSummaryPrompt = """
You are Aegis, preparing a synthesized Health Profile for a doctor's visit.
ALWAYS leave a blank line between every point/paragraph so the Markdown renders correctly.
Follow the exact 4-section template provided in the system context.
""";

  Future<void> reloadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _routerPrompt = prefs.getString('prompt_router') ?? defaultRouterPrompt;
    _generatorPrompt = prefs.getString('prompt_generator') ?? defaultGeneratorPrompt;
    _extractorPrompt = prefs.getString('prompt_extractor') ?? defaultExtractorPrompt;
    _summaryPrompt = prefs.getString('prompt_summary') ?? defaultSummaryPrompt;
    
    _temperature = prefs.getDouble('param_temperature') ?? 0.7;
    _topK = prefs.getInt('param_top_k') ?? 40;
    notifyListeners();
  }

  Future<void> init() async {
    await reloadConfig();
    
    if (useLMStudio) {
      _isModelLoaded = true;
      notifyListeners();
      return;
    }
    
    try {
      final appDir = await getApplicationSupportDirectory();
      final gemmaFile = File('${appDir.path}/gemma.litertlm');
      final qwenFile = File('${appDir.path}/bert.tflite');

      if (!gemmaFile.existsSync() || !qwenFile.existsSync()) {
        _statusMessage = "Models missing. Start download...";
        notifyListeners();
        return; 
      }

      _statusMessage = "Loading models into memory...";
      DebugLogService().log("Inference: Invoking loadModels native...");
      notifyListeners();

      await _channel.invokeMethod('loadModels', {
        'gemmaPath': gemmaFile.path,
        'qwenPath': qwenFile.path,
        'isExternal': true
      });
      
      _isModelLoaded = true;
      _statusMessage = "Ready";
      _loadError = null;
      DebugLogService().log("Inference: Model LOAD SUCCESS");
      notifyListeners();
    } on PlatformException catch (e) {
      _loadError = "Failed to load models: ${e.message}";
      DebugLogService().log("Inference: Model LOAD ERROR: ${e.message}");
      notifyListeners();
    }
  }

  Future<void> downloadModels() async {
    try {
      _loadError = null;
      _statusMessage = "Downloading models natively... (This may take a while)";
      notifyListeners();

      final appDir = await getApplicationSupportDirectory();
      final gemmaPath = '${appDir.path}/gemma.litertlm';
      final qwenPath = '${appDir.path}/bert.tflite';

      double gemmaProgress = File(gemmaPath).existsSync() ? 1.0 : 0.0;
      double qwenProgress = File(qwenPath).existsSync() ? 1.0 : 0.0;

      void updateProgress() {
        _downloadProgress = (gemmaProgress * 0.8) + (qwenProgress * 0.2);
        notifyListeners();
      }

      final List<Future<TaskStatusUpdate>> tasks = [];

      if (gemmaProgress == 0.0) {
        final gemmaTask = DownloadTask(
          url: gemmaUrl,
          filename: 'gemma.litertlm',
          baseDirectory: BaseDirectory.applicationSupport,
          updates: Updates.statusAndProgress,
        );
        tasks.add(FileDownloader().download(
          gemmaTask,
          onProgress: (progress) {
            if (progress >= 0.0) {
              gemmaProgress = progress;
              updateProgress();
            }
          },
        ));
      }

      if (qwenProgress == 0.0) {
        final qwenTask = DownloadTask(
          url: qwenUrl,
          filename: 'bert.tflite',
          baseDirectory: BaseDirectory.applicationSupport,
          updates: Updates.statusAndProgress,
        );
        tasks.add(FileDownloader().download(
          qwenTask,
          onProgress: (progress) {
            if (progress >= 0.0) {
              qwenProgress = progress;
              updateProgress();
            }
          },
        ));
      }

      if (tasks.isNotEmpty) {
        final results = await Future.wait(tasks);
        for (var result in results) {
          if (result.status != TaskStatus.complete) {
            throw Exception("A native download task failed: ${result.status}");
          }
        }
      }

      _downloadProgress = 1.0;
      await init();
    } catch (e) {
      _loadError = "Download failed natively: $e";
      notifyListeners();
    }
  }

  Future<String> generateClinicalSummary(Map<String, dynamic> data) async {
    final userMsg = "Here is the patient data to summarize:\n${json.encode(data)}";
    if (useLMStudio) {
      try {
        final response = await http.post(Uri.parse("$baseUrl/chat/completions"), headers: {"Content-Type": "application/json"}, body: json.encode({"model": "gemma-4-e2b", "messages": [{"role": "system", "content": _summaryPrompt}, {"role": "user", "content": userMsg}], "temperature": 0.1}));
        return json.decode(response.body)['choices'][0]['message']['content'];
      } catch (e) { return "Error: $e"; }
    }
    try {
      return (await _channel.invokeMethod('generate', {'prompt': userMsg, 'system': _summaryPrompt})).toString();
    } catch (e) { return "Error: $e"; }
  }

  Future<Map<String, dynamic>> routeInput(String text, {List<Map<String, String>> history = const []}) async {
    final userPayload = {"history": history, "current_message": text};
    // Constraint: Router only needs ~150 tokens. Higher counts on iOS lead to hallucination.
    return await _queryLLM(_routerPrompt, json.encode(userPayload), temperature: 0.0);
  }

  Future<Map<String, dynamic>> extractLogData(String text) async {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final augmentedPrompt = "Today's Date: $dateStr\n\n${_extractorPrompt.replaceAll("{text}", text)}";
    return await _queryLLM(augmentedPrompt, text, temperature: 0.0);
  }

  List<Map<String, String>> _buildMessageArray({required String query, required Map<String, dynamic> toolContext, required List<Map<String, String>> chatHistory}) {
    final now = DateTime.now();
    final days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    final dayName = days[now.weekday - 1];
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    
    final augmentedPrompt = "Current Local Time: $dayName, $dateStr $timeStr\n\n$_generatorPrompt";
    
    List<Map<String, String>> messages = [{"role": "system", "content": augmentedPrompt}];
    for (var turn in chatHistory) {
      messages.add({"role": turn['role'] == 'human' ? 'user' : 'assistant', "content": turn['content'] ?? ""});
    }
    final leanMemories = (toolContext['personal_memories'] as List? ?? []).map((m) => {"event": m['raw_text'] ?? m['name'], "date": m['event_time']?.toString().substring(0, 10)}).toList();
    final contextBlock = {"personal_memories": leanMemories, "first_aid_content": toolContext['first_aid_content'] ?? [], "ingested": toolContext['ingested']?['extracted_data'], "urgency": toolContext['urgency'] ?? "normal"};
    messages.add({"role": "system", "content": "IMPORTANT EVIDENCE:\n${json.encode(contextBlock)}"});
    messages.add({"role": "user", "content": query});
    return messages;
  }

  Stream<String> generateFinalAnswerStream(String query, Map<String, dynamic> toolContext, {List<Map<String, String>> history = const []}) async* {
    final messages = _buildMessageArray(query: query, toolContext: toolContext, chatHistory: history);
    if (useLMStudio) {
      final client = http.Client();
      try {
        final request = http.Request('POST', Uri.parse("$baseUrl/chat/completions"));
        request.headers['Content-Type'] = 'application/json';
        request.body = json.encode({"model": "gemma-4-e2b", "messages": messages, "temperature": _temperature, "stream": true});
        final response = await client.send(request);
        await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (chunk.startsWith('data: ')) {
            final data = chunk.substring(6).trim();
            if (data == '[DONE]') break;
            try {
              final content = json.decode(data)['choices']?[0]?['delta']?['content'] ?? "";
              if (content.isNotEmpty) yield content;
            } catch (_) {}
          }
        }
      } catch (e) { yield "Error: $e"; } finally { client.close(); }
      return;
    }
    try {
      DebugLogService().log("Inference: Invoking generate stream native...");
      final result = await _channel.invokeMethod('generate', {'prompt': _formatChatTemplate(messages)});
      
      // Clean model artifacts and prefixes like "Aegis: " or "Assistant: "
      String cleanedResult = result.toString()
          .replaceAll(RegExp(r'<start_of_turn>|<end_of_turn>|model\n|user\n|system\n'), '')
          .replaceFirst(RegExp(r'^(Aegis|Assistant|Model|AssistantResponse):\s*', caseSensitive: false), '')
          .trim();

      DebugLogService().log("Inference: generate success, streaming words...");
      
      for (var word in cleanedResult.split(" ")) {
        yield "$word ";
        await Future.delayed(const Duration(milliseconds: 30));
      }
    } catch (e) { 
      DebugLogService().log("Inference: generate ERROR: $e");
      yield "Error: $e"; 
    }
  }

  String _formatChatTemplate(List<Map<String, String>> messages) {
    String buffer = "";
    for (var m in messages) {
      final role = m['role'] == 'system' ? 'system' : (m['role'] == 'user' ? 'user' : 'model');
      buffer += "<start_of_turn>$role\n${m['content']}<end_of_turn>\n";
    }
    buffer += "<start_of_turn>model\n";
    return buffer;
  }

  Future<String> generateFinalAnswer(String query, Map<String, dynamic> toolContext, {List<Map<String, String>> history = const []}) async {
    String full = "";
    await for (final chunk in generateFinalAnswerStream(query, toolContext, history: history)) { full += chunk; }
    return full;
  }

  Future<List<double>?> getEmbedding(String text) async {
    if (useLMStudio) {
      try {
        final response = await http.post(Uri.parse("$baseUrl/embeddings"), headers: {"Content-Type": "application/json"}, body: json.encode({"model": "text-embedding-qwen3-embedding-0.6b", "input": text}));
        final data = json.decode(response.body);
        return (data['data'][0]['embedding'] as List).cast<double>();
      } catch (_) { return null; }
    }
    try {
      final List<dynamic>? result = await _channel.invokeMethod('embed', {'text': text});
      return result?.cast<double>();
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>> _queryLLM(String system, String user, {double temperature = 0.0}) async {
    if (useLMStudio) {
      try {
        final response = await http.post(Uri.parse("$baseUrl/chat/completions"), headers: {"Content-Type": "application/json"}, body: json.encode({"model": "gemma-4-e2b", "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}], "temperature": temperature}));
        return _parseDefensiveJson(json.decode(response.body)['choices'][0]['message']['content']);
      } catch (e) { return {}; }
    }
    try {
      DebugLogService().log("Inference: Invoking queryLLM native...");
      final String? result = await _channel.invokeMethod('generate', {'prompt': user, 'system': system});
      final cleanedResult = result?.replaceAll(RegExp(r'<start_of_turn>|<end_of_turn>|model\n|user\n|system\n'), '').trim() ?? "";
      DebugLogService().log("Inference: queryLLM success, cleaned length: ${cleanedResult.length}");
      return cleanedResult.isNotEmpty ? _parseDefensiveJson(cleanedResult) : {};
    } catch (e) { 
      DebugLogService().log("Inference: queryLLM ERROR: $e");
      return {}; 
    }
  }

  Map<String, dynamic> _parseDefensiveJson(String content) {
    try {
      // 1. Regex-based JSON extraction
      // Finds the first '{' and the last '}' to ignore any rambling text before or after the JSON.
      final jsonRegex = RegExp(r'\{.*\}', dotAll: true);
      final match = jsonRegex.stringMatch(content);
      
      if (match == null) throw Exception("No JSON block found in model output.");

      final cleaned = match
          .replaceAll(RegExp(r'<start_of_turn>|<end_of_turn>|model\n|user\n|system\n|<turn>|assistant\n'), '')
          .trim();
          
      final decoded = json.decode(cleaned) as Map<String, dynamic>;
      
      // 2. Ensure Router schema keys exist
      decoded['tools'] = (decoded['tools'] is String) ? [decoded['tools']] : (decoded['tools'] ?? []);
      decoded['reasoning'] = decoded['reasoning'] ?? "Automated decision.";
      decoded['urgency'] = decoded['urgency'] ?? "normal";
      
      // 3. Ensure Extractor schema keys exist
      decoded['entities'] = (decoded['entities'] is String) ? [{"text": decoded['entities'], "type": "other"}] : (decoded['entities'] ?? []);
      decoded['body_parts'] = (decoded['body_parts'] is String) ? [decoded['body_parts']] : (decoded['body_parts'] ?? []);
      
      return decoded;
    } catch (e) { 
      DebugLogService().log("Inference: JSON Parse Fail. Raw: $content. Error: $e");
      return {
        "tools": ["direct_reply"], 
        "reasoning": "JSON parse error, falling back to direct reply.",
        "urgency": "normal",
        "entities": [], 
        "body_parts": []
      }; 
    }
  }
}
