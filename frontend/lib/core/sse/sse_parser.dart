import 'dart:convert';

class ServerEvent {
  const ServerEvent({required this.name, required this.data});

  final String name;
  final String data;

  Map<String, dynamic>? get json {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String get type => (json?['type'] as String?) ?? name;
}

class SseParser {
  String _buffer = '';

  List<ServerEvent> feed(String chunk) {
    _buffer += chunk;
    final events = <ServerEvent>[];
    int index;
    while ((index = _buffer.indexOf('\n\n')) != -1) {
      final block = _buffer.substring(0, index);
      _buffer = _buffer.substring(index + 2);
      final event = _parseBlock(block);
      if (event != null) {
        events.add(event);
      }
    }
    if (_buffer.length > 65536) {
      _buffer = _buffer.substring(_buffer.length - 65536);
    }
    return events;
  }

  ServerEvent? _parseBlock(String block) {
    String? name;
    final dataLines = <String>[];
    for (final raw in block.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty || line.startsWith(':')) {
        continue;
      }
      final colon = line.indexOf(':');
      final field = colon == -1 ? line : line.substring(0, colon);
      var value = colon == -1 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      if (field == 'event') {
        name = value;
      } else if (field == 'data') {
        dataLines.add(value);
      }
    }
    if (dataLines.isEmpty) {
      return null;
    }
    return ServerEvent(name: name ?? 'message', data: dataLines.join('\n'));
  }
}
