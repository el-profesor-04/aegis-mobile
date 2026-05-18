import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DebugLogService extends ChangeNotifier {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<String> _logs = [];
  List<String> get logs => _logs;
  
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('debug_logs_enabled') ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_logs_enabled', value);
    notifyListeners();
  }

  void log(String message) {
    if (!_isEnabled) return;

    final timestamp = DateTime.now().toLocal().toString().substring(11, 19);
    final entry = "[$timestamp] $message";
    _logs.insert(0, entry); // Newest first
    if (_logs.length > 200) _logs.removeLast();
    
    // Also print to real console
    debugPrint(entry);
    notifyListeners();
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
