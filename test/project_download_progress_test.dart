import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_download_progress.dart';
import 'package:all_hub/hub_liquid_progress.dart';
import 'package:all_hub/hub_wait_indicator.dart';

void main() {
  testWidgets('update progress appears, advances, and disappears reactively',
      (tester) async {
    final active = ValueNotifier<String?>(null);
    final progress = ValueNotifier<double?>(null);
    addTearDown(active.dispose);
    addTearDown(progress.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProjectDownloadProgress(
        projectId: 'shadow-rp', activeProject: active, progress: progress,
      )),
    ));
    expect(find.byType(HubLiquidProgress), findsNothing);

    active.value = 'shadow-rp';
    await tester.pump();
    expect(find.text('Подготовка загрузки…'), findsOneWidget);
    expect(find.byType(HubWaitIndicator), findsOneWidget);
    expect(find.byType(HubLiquidProgress), findsNothing);

    progress.value = 0.45;
    await tester.pump();
    expect(find.text('45%'), findsOneWidget);
    expect(find.byType(HubWaitIndicator), findsNothing);
    expect(tester.widget<HubLiquidProgress>(
        find.byType(HubLiquidProgress)).value, 0.45);

    active.value = 'all-hub';
    await tester.pump();
    expect(find.byType(HubLiquidProgress), findsNothing);
  });

  testWidgets('progress never exposes invalid percentages or claims install',
      (tester) async {
    final active = ValueNotifier<String?>('nova');
    final progress = ValueNotifier<double?>(double.nan);
    addTearDown(active.dispose);
    addTearDown(progress.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ProjectDownloadProgress(projectId: 'nova',
        activeProject: active, progress: progress))));
    expect(find.byType(HubWaitIndicator), findsOneWidget);
    expect(find.byType(HubLiquidProgress), findsNothing);
    progress.value = 1.8;
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    expect(find.byType(HubWaitIndicator), findsNothing);
    expect(tester.widget<HubLiquidProgress>(
      find.byType(HubLiquidProgress)).value, 1.0);
    expect(find.text('Установка'), findsOneWidget);
    expect(find.text('Установлено'), findsNothing);
  });
}
