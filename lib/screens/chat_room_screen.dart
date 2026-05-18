import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/chat_service.dart';
import '../services/dispatcher_service.dart';
import 'package:intl/intl.dart';

class ChatRoomScreen extends StatefulWidget {
  final String sessionId;
  final String title;

  const ChatRoomScreen({super.key, required this.sessionId, required this.title});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // One-time scroll to bottom when opening the conversation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final dispatcher = context.read<DispatcherService>();

    // Scroll as soon as user message is added to DB (implicitly by handleInput)
    _scrollToBottom();
    
    await dispatcher.handleInput(text, sessionId: widget.sessionId);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<ChatMessage>>(
              future: context.watch<ChatService>().getMessages(widget.sessionId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!;
                
                // If AI is thinking, show a temporary message block for streaming
                final dispatcher = context.watch<DispatcherService>();
                
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length + (dispatcher.isProcessing ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Streaming block
                    if (index == messages.length) {
                      return _buildStreamingBlock(dispatcher);
                    }

                    final msg = messages[index];
                    final isUser = msg.role == 'user';
                    
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.white.withOpacity(0.05) : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          border: isUser ? Border.all(color: Colors.white12) : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: msg.content,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(color: isUser ? Colors.white : Colors.white70, height: 1.4),
                                listBullet: TextStyle(color: isUser ? Colors.white : Colors.white70),
                                tableBody: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (!isUser && msg.toolOutputs != null && msg.toolOutputs!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  onTap: () => _showToolOutputs(context, msg.toolOutputs!),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.search_rounded, size: 12, color: Colors.grey),
                                        SizedBox(width: 4),
                                        Text('View Sources', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildActiveToolsOverlay(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Message Aegis...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      fillColor: const Color(0xFF121212),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingBlock(DispatcherService dispatcher) {
    _scrollToBottom(); // Auto-scroll while streaming
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: MarkdownBody(
          data: dispatcher.lastResponse,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white70, height: 1.4),
            listBullet: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveToolsOverlay() {
    return Consumer<DispatcherService>(
      builder: (context, dispatcher, child) {
        if (!dispatcher.isProcessing) return const SizedBox.shrink();
        return Column(
          children: [
            if (dispatcher.activeTools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Wrap(
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
              ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text('Aegis is thinking...', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
          ],
        );
      },
    );
  }

  void _showToolOutputs(BuildContext context, Map<String, dynamic> outputs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tool Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            
            if (outputs['personal_memories'] != null && (outputs['personal_memories'] as List).isNotEmpty) ...[
              const Text('Health History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 8),
              ...((outputs['personal_memories'] as List).map((e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                child: Text("- ${e['raw_text'] ?? e['name']} (${e['event_time']?.toString().substring(0, 10)})", style: const TextStyle(fontSize: 13, color: Colors.white70)),
              )).toList()),
              const SizedBox(height: 16),
            ],

            if (outputs['first_aid_content'] != null && (outputs['first_aid_content'] as List).isNotEmpty) ...[
              const Text('First Aid Knowledge', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              const SizedBox(height: 8),
              ...((outputs['first_aid_content'] as List).map((e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                child: Text(e.toString(), style: const TextStyle(fontSize: 13, color: Colors.white70)),
              )).toList()),
              const SizedBox(height: 16),
            ],
            
            if (outputs['ingested'] != null) ...[
              const Text('Logged Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                child: Text("Symptom: ${outputs['ingested']['extracted_data']?['symptom'] ?? 'N/A'}", style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
