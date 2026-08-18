import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'sse_client.dart';
import 'sse_parser.dart';

class SseClientIO implements SseClient {
  final http.Client _client = http.Client();
  final StreamController<ServerEvent> _controller =
      StreamController<ServerEvent>.broadcast();
  bool _stopped = false;

  @override
  Stream<ServerEvent> get stream => _controller.stream;

  @override
  Future<void> connect(Uri uri, {String? token}) async {
    _run(uri, token);
  }

  Future<void> _run(Uri uri, String? token) async {
    var backoff = const Duration(seconds: 1);
    while (!_stopped) {
      try {
        final request = http.Request('GET', uri);
        request.headers['Accept'] = 'text/event-stream';
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        final response = await _client.send(request);
        if (response.statusCode != 200) {
          throw HttpException('SSE connection failed: ${response.statusCode}');
        }
        backoff = const Duration(seconds: 1);
        final parser = SseParser();
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          if (_stopped) {
            break;
          }
          for (final event in parser.feed(chunk)) {
            _controller.add(event);
          }
        }
        break;
      } catch (error) {
        if (_stopped) {
          break;
        }
        _controller.addError(error);
        await Future<void>.delayed(backoff);
        backoff = Duration(seconds: backoff.inSeconds * 2 > 15 ? 15 : backoff.inSeconds * 2);
      }
    }
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  @override
  void stop() {
    _stopped = true;
    _client.close();
  }
}

SseClient createSseClient() => SseClientIO();
