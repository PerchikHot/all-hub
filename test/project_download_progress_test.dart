import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/project_download_progress.dart';

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
    expect(find.byType(LinearProgressIndicator), findsNothing);

    active.value = 'shadow-rp';
    await tester.pump();
    expect(find.text('Подготовка загрузки…'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator)).value, isNull);

    progress.value = 0.45;
    await tester.pump();
    expect(find.text('Загрузка: 45%'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator)).value, 0.45);

    active.value = 'all-hub';
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
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
    expect(tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator)).value, isNull);
    progress.value = 1.8;
    await tester.pump();
    expect(find.text('Загрузка: 100%'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator)).value, 1.0);
    expect(find.textContaining('подтверждение установки'), findsOneWidget);
  });
}
