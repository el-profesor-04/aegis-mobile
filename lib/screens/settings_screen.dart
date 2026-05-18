import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/inference_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _routerPromptController = TextEditingController();
  final _generatorPromptController = TextEditingController();
  final _extractorPromptController = TextEditingController();
  final _summaryPromptController = TextEditingController();
  
  double _temperature = 0.7;
  int _topK = 40;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final inferenceService = context.read<InferenceService>();
    
    setState(() {
      _routerPromptController.text = prefs.getString('prompt_router') ?? InferenceService.defaultRouterPrompt;
      _generatorPromptController.text = prefs.getString('prompt_generator') ?? InferenceService.defaultGeneratorPrompt;
      _extractorPromptController.text = prefs.getString('prompt_extractor') ?? InferenceService.defaultExtractorPrompt;
      _summaryPromptController.text = prefs.getString('prompt_summary') ?? InferenceService.defaultSummaryPrompt;
      
      _temperature = prefs.getDouble('param_temperature') ?? 0.7;
      _topK = prefs.getInt('param_top_k') ?? 40;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompt_router', _routerPromptController.text);
    await prefs.setString('prompt_generator', _generatorPromptController.text);
    await prefs.setString('prompt_extractor', _extractorPromptController.text);
    await prefs.setString('prompt_summary', _summaryPromptController.text);
    
    await prefs.setDouble('param_temperature', _temperature);
    await prefs.setInt('param_top_k', _topK);
    
    if (mounted) {
      context.read<InferenceService>().reloadConfig();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings applied'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Settings'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _saveSettings,
            icon: const Icon(Icons.check, color: Colors.blueAccent),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Hyperparameters'),
            const SizedBox(height: 16),
            _buildSlider(
              label: 'Temperature', 
              value: _temperature, 
              min: 0.0, 
              max: 1.0, 
              onChanged: (val) => setState(() => _temperature = val)
            ),
            _buildSlider(
              label: 'Top K', 
              value: _topK.toDouble(), 
              min: 1.0, 
              max: 100.0, 
              divisions: 99,
              onChanged: (val) => setState(() => _topK = val.toInt())
            ),
            
            const SizedBox(height: 32),
            _buildSectionHeader('Prompts'),
            const SizedBox(height: 16),
            _buildPromptField('Router Prompt', _routerPromptController),
            const SizedBox(height: 20),
            _buildPromptField('Generator Prompt', _generatorPromptController),
            const SizedBox(height: 20),
            _buildPromptField('Extractor Prompt', _extractorPromptController),
            const SizedBox(height: 20),
            _buildPromptField('Summary Prompt', _summaryPromptController),
            
            const SizedBox(height: 40),
            Center(
              child: TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('prompt_router');
                  await prefs.remove('prompt_generator');
                  await prefs.remove('prompt_extractor');
                  await prefs.remove('prompt_summary');
                  await prefs.remove('param_temperature');
                  await prefs.remove('param_top_k');
                  _loadSettings();
                },
                child: const Text('Reset to Defaults', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
    );
  }

  Widget _buildSlider({required String label, required double value, required double min, required double max, int? divisions, required ValueChanged<double> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text(value.toStringAsFixed(divisions == null ? 2 : 0), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: Colors.blueAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPromptField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: null,
          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}
