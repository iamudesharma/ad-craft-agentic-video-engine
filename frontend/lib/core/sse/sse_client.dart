import 'sse_client_io.dart' if (dart.library.html) 'sse_client_web.dart' as impl;
import 'sse_parser.dart';

abstract class SseClient {
  Stream<ServerEvent> get stream;

  Future<void> connect(Uri uri);

  void stop();

  factory SseClient.create() => impl.createSseClient();
}
