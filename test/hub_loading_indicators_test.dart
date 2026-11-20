import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/hub_liquid_progress.dart';
import 'package:all_hub/hub_wait_indicator.dart';

void main() {
  testWidgets('liquid progress reports real percent and clamps outliers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HubLiquidProgress(value: 0.25)),
    ));
    expect(find.bySemanticsLabel('Прогресс загрузки'), findsOneWidget);
    expect(find.byType(HubLiquidProgress), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HubLiquidProgress(value: 1.5)),
    ));
    expect(find.byType(HubLiquidProgress), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HubLiquidProgress(value: double.nan)),
    ));
    expect(find.byType(HubLiquidProgress), findsOneWidget);
  });

  testWidgets('waiting indicator is distinct and fits compact layout',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: HubWaitIndicator(size: 40))),
    ));
    expect(find.byType(HubWaitIndicator), findsOneWidget);
    expect(find.byType(HubLiquidProgress), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero progress and reduced motion do not crash painters',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: HubLiquidProgress(value: 0)),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
