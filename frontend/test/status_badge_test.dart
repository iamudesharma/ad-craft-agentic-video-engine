import 'package:ad_craft_frontend/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatusBadge renders status text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(status: 'awaiting_approval'))),
    );
    expect(find.text('awaiting approval'), findsOneWidget);
  });
}
