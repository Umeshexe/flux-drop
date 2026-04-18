import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String shortCode;
  final DateTime createdAt;
  final String? fcmToken;

  UserModel({
    required this.uid,
    required this.shortCode,
    required this.createdAt,
    this.fcmToken,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'shortCode': shortCode,
        'createdAt': Timestamp.fromDate(createdAt),
        'fcmToken': fcmToken,
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        uid: map['uid'] as String,
        shortCode: map['shortCode'] as String,
        createdAt: (map['createdAt'] as Timestamp).toDate(),
        fcmToken: map['fcmToken'] as String?,
      );
}
