// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'sse_client.dart';
import 'sse_parser.dart';

class SseClientWeb implements SseClient {
  static const Set<String> _terminalTypes = {
    'job_done',
    'job_completed',
    'job_failed',
    'job_rejected',
  };

  final StreamController<ServerEvent> _controller =
      StreamController<ServerEvent>.broadcast();
  html.EventSource? _source;
  bool _stopped = false;

  @override
  Stream<ServerEvent> get stream => _controller.stream;

  @override
  Future<void> connect(Uri uri) async {
    final source = html.EventSource(uri.toString());
    _source = source;
    final parser = SseParser();
    source.onMessage.listen((message) {
      final data = message.data as String? ?? '';
      for (final event in parser.feed('$data\n\n')) {
        if (!_controller.isClosed) {
          _controller.add(event);
        }
        if (_terminalTypes.contains(event.type)) {
          source.close();
        }
      }
    });
    source.onError.listen((_) {
      if (!_stopped &&
          source.readyState != html.EventSource.CONNECTING &&
          source.readyState == html.EventSource.CLOSED) {
        _controller.close();
      }
    });
  }

  @override
  void stop() {
    _stopped = true;
    _source?.close();
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

SseClient createSseClient() => SseClientWeb();
