import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_hub/eyra_connection_header.dart';

void main() {
  for (final width in [320.0, 360.0, 420.0, 900.0]) {
    testWidgets('Eyra header keeps status readable at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(24),
        child: EyraConnectionHeader(
          avatar: const SizedBox(width: 44, height: 44),
          status: 'Нет подключения',
          connected: false,
          actions: List.generate(6, (i) => IconButton(
            tooltip: 'Действие $i',
            onPressed: () {},
            icon: const Icon(Icons.settings),
          )),
        ),
      ))));
      expect(find.text('Локальная модель'), findsOneWidget);
      expect(find.text('Нет подключения'), findsOneWidget);
      expect(find.byType(IconButton), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      final titleSize = tester.getSize(find.text('Локальная модель'));
      expect(titleSize.width, greaterThan(90));
    });
  }
}
