import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:haven/main.dart';
import 'package:haven/storage/haven_cache.dart';

void main() {
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('haven_test_');
    await HavenCache.init(path: tempDir.path);
  });

  testWidgets('HAVEN app renders tab shell', (WidgetTester tester) async {
    await tester.pumpWidget(const HavenApp());
    await tester.pump();

    expect(find.text('HAVEN'), findsOneWidget);
    expect(find.text('MANUALS'), findsOneWidget);
    expect(find.text('Manuals'), findsWidgets);
    expect(find.text('News'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
  });
}
