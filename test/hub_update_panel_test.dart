import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/hub_update_panel.dart';
import 'package:all_hub/hub_liquid_progress.dart';

void main() {
  test('byte formatting uses human readable units', () {
    expect(HubUpdatePanel.formatBytes(640 * 1024 * 1024), '640.0 МБ');
    expect(HubUpdatePanel.formatBytes(-1), '—');
    expect(HubUpdatePanel.formatBytes(double.nan), '—');
  });

  testWidgets('reference update panel displays measured data', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: HubUpdatePanel(
        progress: .67,
        installedVersion: 'v1.8.0',
        availableVersion: 'v1.9.0',
        downloadedBytes: 428700000,
        totalBytes: 640000000,
        bytesPerSecond: 32400000,
      )),
    )));
    expect(find.text('67%'), findsOneWidget);
    expect(find.textContaining('v1.8.0'), findsOneWidget);
    expect(find.byType(HubLiquidProgress), findsOneWidget);
    expect(find.text('Загрузка'), findsOneWidget);
    expect(find.text('Установка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause and cancel appear only when wired', (tester) async {
    var paused = false;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HubUpdatePanel(
      progress: .2,
      onPause: () => paused = true,
      onCancel: () => cancelled = true,
    ))));
    await tester.tap(find.text('Пауза'));
    await tester.tap(find.text('Отмена'));
    expect(paused, isTrue);
    expect(cancelled, isTrue);
  });

  testWidgets('stage tracker accepts real unpacking state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: HubUpdatePanel(
        progress: 1,
        stage: HubUpdateStage.unpacking,
      )),
    )));
    expect(find.text('Распаковка'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('absurd ETA does not overflow duration', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: HubUpdatePanel(
        progress: .01,
        downloadedBytes: 1,
        totalBytes: 1000000000000,
        bytesPerSecond: .000001,
      )),
    )));
    expect(find.text('Осталось: —'), findsOneWidget);
  });

  testWidgets('unknown transfer speed does not invent remaining time',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      HubUpdatePanel(progress: 0),
    )));
    expect(find.text('Осталось: —'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });
}
