import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floodroute/main.dart';

void main() {
  testWidgets('Home screen shows the map widget', (WidgetTester tester) async {
    await tester.pumpWidget(const FloodRouteApp());

    expect(find.text('FloodRoute'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  test('Android manifest includes Internet permission for OSM tiles', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');

    expect(manifestFile.existsSync(), isTrue);
    final content = manifestFile.readAsStringSync();
    expect(content, contains('<uses-permission android:name="android.permission.INTERNET"/>'));
  });
}
