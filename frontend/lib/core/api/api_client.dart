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
    String? brandGuidelines,
    String aspectRatio = '9:16',
    bool? hitlEnabled,
  }) async {
    final data = <String, dynamic>{
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'hitl_enabled': ?hitlEnabled,
    };
    final brand = (brandGuidelines ?? '').trim();
    if (brand.isNotEmpty) {
      data['brand_guidelines'] = brand;
    }
    final response = await _dio.post('/api/v1/generate', data: data);
    return (response.data as Map<String, dynamic>)['job_id'] as String;
  }

  Future<void> approve(
    String jobId, {
    required bool approved,
    String? feedback,
  }) async {
    final resolvedFeedback = (feedback == null || feedback.isEmpty) ? null : feedback;
    await _dio.post('/api/v1/jobs/$jobId/approve', data: {
      'decision': approved ? 'approved' : 'rejected',
      'feedback': resolvedFeedback,
    });
  }

  String resolveUrl(String pathOrUrl) => pathOrUrl.startsWith('http')
      ? pathOrUrl
      : '${_dio.options.baseUrl}$pathOrUrl';
}
