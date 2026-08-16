import 'package:flutter/material.dart';

class RetryImage extends StatefulWidget {
  const RetryImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;

  @override
  State<RetryImage> createState() => _RetryImageState();
}

class _RetryImageState extends State<RetryImage> {
  static const int _maxAttempts = 8;
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant RetryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _attempt = 0;
    }
  }

  void _scheduleRetry() {
    if (!mounted || _attempt >= _maxAttempts) {
      return;
    }
    _attempt += 1;
    Future<void>.delayed(Duration(seconds: _attempt * 2), () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.url,
      key: ValueKey('$_attempt-${widget.url}'),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        _scheduleRetry();
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.black26,
          child: const Icon(Icons.image_outlined),
        );
      },
    );
  }
}
