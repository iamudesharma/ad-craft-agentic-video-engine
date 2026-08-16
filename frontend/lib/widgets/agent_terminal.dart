import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class AgentTerminal extends ConsumerStatefulWidget {
  const AgentTerminal({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<AgentTerminal> createState() => _AgentTerminalState();
}

class _AgentTerminalState extends ConsumerState<AgentTerminal> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final terminal = ref.watch(agentTerminalProvider(widget.jobId));
    _scrollToBottom();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Agent Terminal',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                if (terminal.stage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'running: ${terminal.stage}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.lightBlueAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                terminal.lines.join('\n'),
                style: const TextStyle(
                  fontFamily: 'Menlo',
                  fontFamilyFallback: ['monospace'],
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFFC9D1D9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
