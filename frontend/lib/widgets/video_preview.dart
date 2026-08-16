import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPreview extends StatefulWidget {
  const VideoPreview({
    super.key,
    required this.url,
    required this.height,
    this.hint = 'Video renders after approval',
  });

  final String? url;
  final double height;
  final String hint;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _retrying = false;
  int _initAttempt = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _initController();
    }
  }

  Future<void> _initController() async {
    _retryTimer?.cancel();
    _failed = false;
    _retrying = false;
    _initAttempt = 0;
    await _controller?.dispose();
    _controller = null;
    final url = widget.url;
    if (url == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) {
        return;
      }
      if (_initAttempt < 4) {
        _initAttempt += 1;
        setState(() => _retrying = true);
        _retryTimer = Timer(Duration(seconds: _initAttempt * 3), _initController);
        return;
      }
      setState(() {
        _failed = true;
        _retrying = false;
      });
      return;
    }
    if (mounted) {
      setState(() => _controller = controller);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: controller == null
          ? Center(
              child: _failed
                  ? const Text('Video unavailable')
                  : _retrying
                      ? const Text('Loading video...')
                      : Text(widget.hint),
            )
          : ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final aspect = value.isInitialized
                    ? value.aspectRatio
                    : 9 / 16;
                final height = (widget.height - 44).clamp(0.0, double.infinity).toDouble();
                final width = height * aspect;
                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: width.clamp(0.0, double.infinity).toDouble(),
                            child: AspectRatio(
                              aspectRatio: aspect,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      height: 44,
                      color: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            onPressed: () {
                              value.isPlaying
                                  ? controller.pause()
                                  : controller.play();
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: value.position.inMilliseconds
                                  .toDouble()
                                  .clamp(0.0, value.duration.inMilliseconds.toDouble()),
                              max: value.duration.inMilliseconds
                                  .toDouble()
                                  .clamp(1.0, double.infinity),
                              onChanged: (ms) => controller.seekTo(
                                Duration(milliseconds: ms.round()),
                              ),
                            ),
                          ),
                          Text(
                            '${value.position.inMinutes}:'
                            '${(value.position.inSeconds % 60).toString().padLeft(2, '0')}'
                            ' / '
                            '${value.duration.inMinutes}:'
                            '${(value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
