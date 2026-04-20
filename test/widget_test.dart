import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fluxdrop/models/transfer_model.dart';

void main() {
  test('TransferStatus defaults unknown values to pending', () {
    final transfer = TransferModel.fromMap({
      'transferId': 't1',
      'senderId': 's1',
      'receiverId': 'r1',
      'senderCode': 'A4X9K2',
      'receiverCode': 'B7M2Q9',
      'files': const [],
      'status': 'mystery-status',
      'uploadProgress': 0.0,
      'downloadProgress': 0.0,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 19)),
      'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 4, 20)),
      'totalBytes': 0,
      'transferredBytes': 0,
    });

    expect(transfer.status, TransferStatus.pending);
  });
}
