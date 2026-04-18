// App-wide constants for FluxDrop
class AppConstants {
  // Short code settings
  static const int shortCodeLength = 6;
  static const String shortCodeAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Crockford Base32 — no O/0, I/1, L

  // Transfer settings
  static const int maxFileSizeBytes = 500 * 1024 * 1024; // 500 MB ceiling
  static const int transferTtlHours = 24; // Offline queue TTL
  static const int chunkSizeBytes = 256 * 1024; // 256 KB chunks for streaming

  // Firestore collection names
  static const String usersCollection = 'users';
  static const String transfersCollection = 'transfers';

  // Transfer statuses
  static const String statusPending = 'pending';
  static const String statusUploading = 'uploading';
  static const String statusUploaded = 'uploaded';
  static const String statusDownloading = 'downloading';
  static const String statusCompleted = 'completed';
  static const String statusFailed = 'failed';
  static const String statusExpired = 'expired';
  static const String statusRejected = 'rejected';

  // App theme
  static const String appName = 'FluxDrop';
}
