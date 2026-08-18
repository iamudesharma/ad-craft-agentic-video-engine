import 'package:ad_craft_frontend/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JobSummary', () {
    test('parses new fields', () {
      final summary = JobSummary.fromJson({
        'job_id': 'j1',
        'status': 'completed',
        'aspect_ratio': '9:16',
        'title': 'Craft Coffee',
        'prompt': 'A moody craft coffee ad',
        'has_storyboard': true,
        'favorite': true,
        'created_at': '2026-08-18T10:00:00Z',
      });
      expect(summary.title, 'Craft Coffee');
      expect(summary.prompt, 'A moody craft coffee ad');
      expect(summary.hasStoryboard, isTrue);
      expect(summary.favorite, isTrue);
    });

    test('falls back to defaults when fields are missing', () {
      final summary = JobSummary.fromJson({'job_id': 'j1'});
      expect(summary.title, '');
      expect(summary.prompt, '');
      expect(summary.hasStoryboard, isFalse);
      expect(summary.favorite, isFalse);
      expect(summary.status, 'unknown');
    });

    test('copyWith updates favorite without losing other fields', () {
      final summary = JobSummary.fromJson({
        'job_id': 'j1',
        'status': 'completed',
        'title': 'Craft Coffee',
        'favorite': false,
      });
      final updated = summary.copyWith(favorite: true, status: 'running');
      expect(updated.favorite, isTrue);
      expect(updated.status, 'running');
      expect(updated.title, 'Craft Coffee');
    });
  });

  group('JobListPage', () {
    test('parses response envelope', () {
      final page = JobListPage.fromJson({
        'items': [
          {
            'job_id': 'j1',
            'status': 'completed',
            'aspect_ratio': '9:16',
            'title': 'Craft Coffee',
            'prompt': 'brief',
            'has_storyboard': true,
            'favorite': false,
            'created_at': '2026-08-18T10:00:00Z',
          }
        ],
        'total': 1,
        'page': 1,
        'per_page': 20,
      });
      expect(page.items, hasLength(1));
      expect(page.total, 1);
      expect(page.page, 1);
      expect(page.perPage, 20);
      expect(page.hasMore, isFalse);
    });

    test('hasMore reflects remaining pages', () {
      final page = JobListPage(
        items: const [],
        total: 45,
        page: 1,
        perPage: 20,
      );
      expect(page.hasMore, isTrue);
    });
  });
}
