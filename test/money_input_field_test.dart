import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/core.dart';

void main() {
  group('MoneyInputField widget tests [FIX-MONEY-1]', () {
    testWidgets('renders label and initialValue formatted', (tester) async {
      double? updatedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyInputField(
              initialValue: 1500.50,
              label: 'Principal Amount',
              onChanged: (val) => updatedValue = val,
            ),
          ),
        ),
      );

      expect(find.text('Principal Amount'), findsOneWidget);
      expect(find.text('1500.5'), findsOneWidget);
      expect(find.text('₹ '), findsOneWidget);
    });

    testWidgets('accepts valid 2-decimal money and refuses 3rd decimal digit', (tester) async {
      double? lastEmitted;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyInputField(
              label: 'Loan Amount',
              onChanged: (val) => lastEmitted = val,
            ),
          ),
        ),
      );

      final finder = find.byType(TextFormField);

      // 1. Enter 154
      await tester.enterText(finder, '154');
      await tester.pump();
      expect(lastEmitted, 154.0);

      // 2. Enter 154.32
      await tester.enterText(finder, '154.32');
      await tester.pump();
      expect(lastEmitted, 154.32);

      // 3. Attempting to enter 154.325 is rejected by input formatter, retaining 154.32
      await tester.enterText(finder, '154.325');
      await tester.pump();
      // Should not have updated to 154.325
      expect(lastEmitted, 154.32);
      expect(find.text('154.32'), findsOneWidget);
    });

    testWidgets('clearing input emits null or shows required error if isRequired', (tester) async {
      double? lastEmitted = 100.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyInputField(
              isRequired: true,
              label: 'Principal',
              onChanged: (val) => lastEmitted = val,
            ),
          ),
        ),
      );

      final finder = find.byType(TextFormField);
      await tester.enterText(finder, '500');
      await tester.pump();
      expect(lastEmitted, 500.0);

      await tester.enterText(finder, '');
      await tester.pump();
      expect(lastEmitted, isNull);
      expect(find.text('This field is required'), findsOneWidget);
    });
  });
}
