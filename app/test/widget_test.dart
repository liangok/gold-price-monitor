import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldprice/ui/widgets/price_line_chart.dart';

void main() {
  testWidgets('折线图可以离线绘制', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: PriceLineChart(
              values: <double>[1, 3, 2, 5, 4],
              labels: <String>['a', 'b', 'c', 'd', 'e'],
              lineColor: Colors.blue,
              averageLine: 3,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
