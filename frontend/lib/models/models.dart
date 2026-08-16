class JobSummary {
  const JobSummary({
    required this.jobId,
    required this.status,
    required this.aspectRatio,
    required this.createdAt,
  });

  final String jobId;
  final String status;
  final String aspectRatio;
  final DateTime createdAt;

  factory JobSummary.fromJson(Map<String, dynamic> json) => JobSummary(
        jobId: json['job_id'] as String,
        status: json['status'] as String? ?? 'unknown',
        aspectRatio: json['aspect_ratio'] as String? ?? '9:16',
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

class Scene {
  const Scene({
    required this.sceneId,
    required this.narration,
    required this.visualPrompt,
    required this.durationSeconds,
    this.captionText = '',
  });

  final int sceneId;
  final String narration;
  final String visualPrompt;
  final int durationSeconds;
  final String captionText;

  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
        sceneId: json['scene_id'] as int,
        narration: json['narration'] as String? ?? '',
        visualPrompt: json['visual_prompt'] as String? ?? '',
        durationSeconds: json['duration_seconds'] as int? ?? 5,
        captionText: json['caption_text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'scene_id': sceneId,
        'narration': narration,
        'visual_prompt': visualPrompt,
        'duration_seconds': durationSeconds,
        'caption_text': captionText,
      };

  Scene copyWith({
    String? narration,
    String? visualPrompt,
    int? durationSeconds,
    String? captionText,
  }) =>
      Scene(
        sceneId: sceneId,
        narration: narration ?? this.narration,
        visualPrompt: visualPrompt ?? this.visualPrompt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        captionText: captionText ?? this.captionText,
      );
}

class Storyboard {
  const Storyboard({
    required this.title,
    required this.targetAudience,
    required this.aspectRatio,
    required this.scenes,
  });

  final String title;
  final String targetAudience;
  final String aspectRatio;
  final List<Scene> scenes;

  factory Storyboard.fromJson(Map<String, dynamic> json) => Storyboard(
        title: json['title'] as String? ?? '',
        targetAudience: json['target_audience'] as String? ?? '',
        aspectRatio: json['aspect_ratio'] as String? ?? '9:16',
        scenes: (json['scenes'] as List? ?? [])
            .map((s) => Scene.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'target_audience': targetAudience,
        'aspect_ratio': aspectRatio,
        'scenes': scenes.map((s) => s.toJson()).toList(),
      };
}

class JobDetail {
  const JobDetail({
    required this.jobId,
    required this.status,
    required this.aspectRatio,
    this.storyboard,
    this.error,
    this.videoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String jobId;
  final String status;
  final String aspectRatio;
  final Storyboard? storyboard;
  final String? error;
  final String? videoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory JobDetail.initial(String jobId) => JobDetail(
        jobId: jobId,
        status: 'pending',
        aspectRatio: '9:16',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  factory JobDetail.fromJson(Map<String, dynamic> json) => JobDetail(
        jobId: json['job_id'] as String,
        status: json['status'] as String? ?? 'unknown',
        aspectRatio: json['aspect_ratio'] as String? ?? '9:16',
        storyboard: json['storyboard'] == null
            ? null
            : Storyboard.fromJson(json['storyboard'] as Map<String, dynamic>),
        error: json['error'] as String?,
        videoUrl: json['video_url'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );

  JobDetail copyWith({
    String? status,
    Storyboard? storyboard,
    String? error,
    String? videoUrl,
  }) =>
      JobDetail(
        jobId: jobId,
        status: status ?? this.status,
        aspectRatio: aspectRatio,
        storyboard: storyboard ?? this.storyboard,
        error: error ?? this.error,
        videoUrl: videoUrl ?? this.videoUrl,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool get isTerminal =>
      status == 'completed' || status == 'failed' || status == 'rejected';
}
