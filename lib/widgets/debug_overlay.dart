import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/debug_log_service.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;
  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugLogService>(
      builder: (context, debugService, child) {
        if (!debugService.isEnabled) return widget.child;

        return Stack(
          children: [
            widget.child,
            if (_isVisible)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                top: 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('AEGIS DEBUG CONSOLE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70, size: 18),
                                    onPressed: () => debugService.clear(),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                                    onPressed: () => setState(() => _isVisible = false),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: debugService.logs.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  debugService.logs[index],
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 100,
              right: 20,
              child: FloatingActionButton.small(
                backgroundColor: _isVisible ? Colors.redAccent : Colors.blueAccent.withOpacity(0.5),
                onPressed: () => setState(() => _isVisible = !_isVisible),
                child: Icon(_isVisible ? Icons.bug_report : Icons.bug_report_outlined, size: 18),
              ),
            ),
          ],
        );
      },
    );
  }
}
