import 'package:dio/dio.dart';

import '../../models/models.dart';

class ApiRepository {
  ApiRepository(this._dio);

  final Dio _dio;

  Future<List<JobSummary>> listJobs() async {
    final response = await _dio.get('/api/v1/jobs');
    final list = response.data as List;
    return list.map((e) => JobSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<JobDetail> getJob(String jobId) async {
    final response = await _dio.get('/api/v1/jobs/$jobId');
    return JobDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> generate({
    required String prompt,
    BrandGuidelines? brandGuidelines,
    String aspectRatio = '9:16',
    bool? hitlEnabled,
  }) async {
    final data = <String, dynamic>{
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'hitl_enabled': ?hitlEnabled,
    };
    if (brandGuidelines != null && !brandGuidelines.isEmpty) {
      data['brand_guidelines'] = brandGuidelines.toJson();
    }
    final response = await _dio.post('/api/v1/generate', data: data);
    return (response.data as Map<String, dynamic>)['job_id'] as String;
  }

  Future<void> approve(
    String jobId, {
    required bool approved,
    String? feedback,
    Storyboard? storyboard,
  }) async {
    final resolvedFeedback = (feedback == null || feedback.isEmpty) ? null : feedback;
    final data = <String, dynamic>{
      'decision': approved ? 'approved' : 'rejected',
      'feedback': resolvedFeedback,
    };
    if (storyboard != null) {
      data['storyboard'] = storyboard.toJson();
    }
    await _dio.post('/api/v1/jobs/$jobId/approve', data: data);
  }

  Future<void> regenerate(String jobId, Storyboard storyboard) async {
    await _dio.post('/api/v1/jobs/$jobId/regenerate', data: {
      'storyboard': storyboard.toJson(),
    });
  }

  String resolveUrl(String pathOrUrl) => pathOrUrl.startsWith('http')
      ? pathOrUrl
      : '${_dio.options.baseUrl}$pathOrUrl';
}
