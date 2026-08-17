import 'package:flutter/material.dart';

import '../core/config.dart';
import '../models/models.dart';
import 'retry_image.dart';

class StoryboardEditor extends StatefulWidget {
  const StoryboardEditor({
    super.key,
    required this.jobId,
    required this.storyboard,
    this.enabled = true,
    this.dirtyHint,
    this.onStoryboardChanged,
  });

  final String jobId;
  final Storyboard? storyboard;
  final bool enabled;
  final String? dirtyHint;
  final ValueChanged<Storyboard>? onStoryboardChanged;

  @override
  State<StoryboardEditor> createState() => _StoryboardEditorState();
}

class _StoryboardEditorState extends State<StoryboardEditor> {
  final Map<int, TextEditingController> _controllers = {};
  List<Scene>? _scenes;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant StoryboardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storyboard != oldWidget.storyboard) {
      _syncFromWidget();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncFromWidget() {
    final board = widget.storyboard;
    if (board == null || _dirty) {
      return;
    }
    _scenes = board.scenes.map((s) => s).toList();
    _rebuildControllers();
  }

  void _rebuildControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final scene in _scenes ?? []) {
      _controllers[scene.sceneId] = TextEditingController(text: scene.narration);
      _controllers[scene.sceneId * 1000 + 1] =
          TextEditingController(text: scene.captionText);
      _controllers[scene.sceneId * 1000 + 2] =
          TextEditingController(text: scene.visualPrompt);
    }
  }

  TextEditingController _controller(int key) =>
      _controllers.putIfAbsent(key, () => TextEditingController());

  void _updateScene(int index, Scene scene) {
    setState(() {
      _dirty = true;
      _scenes![index] = scene;
    });
    _emitStoryboard();
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (!widget.enabled || _scenes == null) {
      return;
    }
    setState(() {
      final scene = _scenes!.removeAt(oldIndex);
      _scenes!.insert(newIndex, scene);
      _renumberScenes();
    });
    _emitStoryboard();
  }

  /// Re-assign 0-indexed scene ids after a reorder. Controllers hold the
  /// edited text and travel with their scene, so remap them to the new ids.
  void _renumberScenes() {
    final oldControllers = Map<int, TextEditingController>.from(_controllers);
    _controllers.clear();
    for (var i = 0; i < _scenes!.length; i++) {
      final oldId = _scenes![i].sceneId;
      _scenes![i] = _scenes![i].copyWith(sceneId: i);
      _controllers[i] = oldControllers[oldId]!;
      _controllers[i * 1000 + 1] = oldControllers[oldId * 1000 + 1]!;
      _controllers[i * 1000 + 2] = oldControllers[oldId * 1000 + 2]!;
    }
    _dirty = true;
  }

  void _emitStoryboard() {
    final board = widget.storyboard;
    if (board == null || _scenes == null) {
      return;
    }
    widget.onStoryboardChanged?.call(Storyboard(
      title: board.title,
      targetAudience: board.targetAudience,
      aspectRatio: board.aspectRatio,
      scenes: List.of(_scenes!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.storyboard;
    if (board == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Waiting for storyboard...'),
          ],
        ),
      );
    }
    final scenes = _scenes ?? board.scenes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  board.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                board.aspectRatio,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_dirty && widget.dirtyHint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              widget.dirtyHint!,
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          ),
        if (!widget.enabled)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Fields locked while the job is processing',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: scenes.length,
            itemBuilder: (context, index) {
              final scene = scenes[index];
              return _SceneCard(
                key: ValueKey(scene.sceneId),
                scene: scene,
                jobId: widget.jobId,
                enabled: widget.enabled,
                index: index,
                narrationController: _controller(scenes[index].sceneId),
                captionController: _controller(scenes[index].sceneId * 1000 + 1),
                promptController: _controller(scenes[index].sceneId * 1000 + 2),
                onChanged: (scene) => _updateScene(index, scene),
              );
            },
            onReorderItem: _onReorder,          ),
        ),
      ],
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({
    super.key,
    required this.scene,
    required this.jobId,
    required this.enabled,
    required this.index,
    required this.narrationController,
    required this.captionController,
    required this.promptController,
    required this.onChanged,
  });

  final Scene scene;
  final String jobId;
  final bool enabled;
  final int index;
  final TextEditingController narrationController;
  final TextEditingController captionController;
  final TextEditingController promptController;
  final ValueChanged<Scene> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: RetryImage(
                    url: '$apiBaseUrl/media/$jobId/images/scene_${scene.sceneId}.jpg',
                    width: 84,
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: narrationController,
                        enabled: enabled,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Narration',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            onChanged(scene.copyWith(narration: value)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: captionController,
                        enabled: enabled,
                        decoration: const InputDecoration(
                          labelText: 'Caption',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            onChanged(scene.copyWith(captionText: value)),
                      ),
                    ],
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 8),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.drag_handle, size: 20),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: promptController,
              enabled: enabled,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Visual prompt',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (value) =>
                  onChanged(scene.copyWith(visualPrompt: value)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Duration', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: scene.durationSeconds.toDouble(),
                    min: 3,
                    max: 12,
                    divisions: 9,
                    label: '${scene.durationSeconds}s',
                    onChanged: enabled
                        ? (value) => onChanged(
                              scene.copyWith(durationSeconds: value.round()),
                            )
                        : null,
                  ),
                ),
                Text(
                  '${scene.durationSeconds}s',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}