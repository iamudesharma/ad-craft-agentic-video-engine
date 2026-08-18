import 'package:dio/dio.dart';

import '../../models/models.dart';

class ApiRepository {
  ApiRepository(this._dio) {
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        final path = error.requestOptions.path;
        if (error.response?.statusCode == 401 &&
            !path.startsWith('/api/v1/auth')) {
          onUnauthorized?.call();
        }
        handler.next(error);
      },
    ));
  }

  final Dio _dio;

  /// Invoked when any authenticated call returns 401 (session expired).
  void Function()? onUnauthorized;

  void setToken(String? token) {
    if (token == null) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/api/v1/auth/login', data: {
      'email': email,
      'password': password,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _dio.post('/api/v1/auth/signup', data: {
      'email': email,
      'password': password,
      'name': name,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/api/v1/auth/me');
    return response.data as Map<String, dynamic>;
  }

  Future<Org> completeOnboarding({
    required String orgName,
    BrandGuidelines? brandGuidelines,
  }) async {
    final data = <String, dynamic>{'org_name': orgName};
    if (brandGuidelines != null && !brandGuidelines.isEmpty) {
      data['brand_guidelines'] = brandGuidelines.toJson();
    }
    final response = await _dio.post('/api/v1/onboarding', data: data);
    return Org.fromJson(
        (response.data as Map<String, dynamic>)['org'] as Map<String, dynamic>);
  }

  Future<Org> getOrg() async {
    final response = await _dio.get('/api/v1/orgs/me');
    return Org.fromJson(
        (response.data as Map<String, dynamic>)['org'] as Map<String, dynamic>);
  }

  Future<Org> updateOrg({
    String? name,
    BrandGuidelines? brandGuidelines,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) {
      data['name'] = name;
    }
    if (brandGuidelines != null) {
      data['brand_guidelines'] = brandGuidelines.toJson();
    }
    final response = await _dio.put('/api/v1/orgs/me', data: data);
    return Org.fromJson(
        (response.data as Map<String, dynamic>)['org'] as Map<String, dynamic>);
  }

  Future<OrgMember> inviteMember({
    required String email,
    required String role,
  }) async {
    final response = await _dio.post('/api/v1/orgs/me/members', data: {
      'email': email,
      'role': role,
    });
    return OrgMember.fromJson(
        (response.data as Map<String, dynamic>)['member'] as Map<String, dynamic>);
  }

  Future<OrgMember> updateMemberRole(String memberId, String role) async {
    final response = await _dio.patch('/api/v1/orgs/me/members/$memberId', data: {
      'role': role,
    });
    return OrgMember.fromJson(
        (response.data as Map<String, dynamic>)['member'] as Map<String, dynamic>);
  }

  Future<void> removeMember(String memberId) async {
    await _dio.delete('/api/v1/orgs/me/members/$memberId');
  }

  Future<JobListPage> listJobs({
    int page = 1,
    int perPage = 20,
    String? status,
    String? aspectRatio,
    String? query,
    bool favoritesOnly = false,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'status': ?status,
      'aspect_ratio': ?aspectRatio,
      if (query != null && query.isNotEmpty) 'q': query,
      if (favoritesOnly) 'favorites_only': 'true',
    };
    final response = await _dio.get('/api/v1/jobs', queryParameters: params);
    return JobListPage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<bool> setFavorite(String jobId, bool favorite) async {
    final response = await _dio.patch(
      '/api/v1/jobs/$jobId/favorite',
      data: {'favorite': favorite},
    );
    return (response.data as Map<String, dynamic>)['favorite'] as bool;
  }

  Future<String> duplicate(String jobId, String mode) async {
    final response = await _dio.post(
      '/api/v1/jobs/$jobId/duplicate',
      data: {'mode': mode},
    );
    return (response.data as Map<String, dynamic>)['job_id'] as String;
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