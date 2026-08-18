class BrandGuidelines {
  const BrandGuidelines({
    this.brandName,
    this.tagline,
    this.toneOfVoice,
    this.colors,
    this.typography,
    this.visualStyle,
    this.doList,
    this.dontList,
    this.targetAudience,
  });

  final String? brandName;
  final String? tagline;
  final String? toneOfVoice;
  final List<String>? colors;
  final String? typography;
  final String? visualStyle;
  final List<String>? doList;
  final List<String>? dontList;
  final String? targetAudience;

  bool get isEmpty =>
      brandName == null &&
      tagline == null &&
      toneOfVoice == null &&
      colors == null &&
      typography == null &&
      visualStyle == null &&
      doList == null &&
      dontList == null &&
      targetAudience == null;

  Map<String, dynamic> toJson() => {
        if (brandName != null) 'brand_name': brandName,
        if (tagline != null) 'tagline': tagline,
        if (toneOfVoice != null) 'tone_of_voice': toneOfVoice,
        if (colors != null) 'colors': colors,
        if (typography != null) 'typography': typography,
        if (visualStyle != null) 'visual_style': visualStyle,
        if (doList != null) 'do_list': doList,
        if (dontList != null) 'dont_list': dontList,
        if (targetAudience != null) 'target_audience': targetAudience,
      };
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.name = '',
  });

  final String id;
  final String email;
  final String name;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class OrgMember {
  const OrgMember({
    required this.id,
    required this.userId,
    required this.role,
    this.email = '',
    this.name = '',
  });

  final String id;
  final String userId;
  final String role;
  final String email;
  final String name;

  factory OrgMember.fromJson(Map<String, dynamic> json) => OrgMember(
        id: json['id'] as String,
        userId: json['user_id'] as String? ?? '',
        role: json['role'] as String? ?? 'member',
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || role == 'owner';
}

class Org {
  const Org({
    required this.id,
    required this.name,
    this.brandGuidelines,
    this.myRole = 'member',
    this.members = const [],
  });

  final String id;
  final String name;
  final BrandGuidelines? brandGuidelines;
  final String myRole;
  final List<OrgMember> members;

  factory Org.fromJson(Map<String, dynamic> json) => Org(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        brandGuidelines: json['brand_guidelines'] == null
            ? null
            : _guidelinesFromMap(json['brand_guidelines'] as Map<String, dynamic>),
        myRole: json['my_role'] as String? ?? 'member',
        members: (json['members'] as List? ?? [])
            .map((m) => OrgMember.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  bool get canManage => myRole == 'owner' || myRole == 'admin';

  static BrandGuidelines? _guidelinesFromMap(Map<String, dynamic> json) {
    final g = BrandGuidelines(
      brandName: json['brand_name'] as String?,
      tagline: json['tagline'] as String?,
      toneOfVoice: json['tone_of_voice'] as String?,
      colors: _stringList(json['colors']),
      typography: json['typography'] as String?,
      visualStyle: json['visual_style'] as String?,
      doList: _stringList(json['do_list']),
      dontList: _stringList(json['dont_list']),
      targetAudience: json['target_audience'] as String?,
    );
    return g.isEmpty ? null : g;
  }

  static List<String>? _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }
}

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
    int? sceneId,
    String? narration,
    String? visualPrompt,
    int? durationSeconds,
    String? captionText,
  }) =>
      Scene(
        sceneId: sceneId ?? this.sceneId,
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
