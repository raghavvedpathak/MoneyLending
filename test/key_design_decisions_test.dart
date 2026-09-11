import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('Key Room Design Decisions Tests (§4.2)', () {
    test('RecordType string conversion matches spec', () {
      expect(RecordType.GIVEN.name, 'GIVEN');
      expect(RecordType.TAKEN.name, 'TAKEN');
      expect(RecordType.fromString('GIVEN'), RecordType.GIVEN);
      expect(RecordType.fromString('TAKEN'), RecordType.TAKEN);
      expect(RecordType.fromString('INVALID'), isNull);
    });

    test('RecordStatus string conversion matches spec', () {
      expect(RecordStatus.ACTIVE.name, 'ACTIVE');
      expect(RecordStatus.SETTLED.name, 'SETTLED');
      expect(RecordStatus.fromString('ACTIVE'), RecordStatus.ACTIVE);
      expect(RecordStatus.fromString('SETTLED'), RecordStatus.SETTLED);
      expect(RecordStatus.fromString('UNKNOWN'), isNull);
    });

    test('DeleteConfirmationState model adheres to [FIX-DELETESTATE-1]', () {
      const state = DeleteConfirmationState(
        recordId: 'rec-123',
        linkedCount: 3,
      );

      expect(state.recordId, 'rec-123');
      expect(state.linkedCount, 3);
      expect(
        state,
        const DeleteConfirmationState(recordId: 'rec-123', linkedCount: 3),
      );
    });

    test('RecordLinkedTakenException adheres to [FIX-DEV-TOCTOU-1]', () {
      const exception = RecordLinkedTakenException(linkedCount: 2);
      expect(exception.linkedCount, 2);
      expect(exception.toString(), contains('2 TAKEN record(s)'));
    });
  });
}
