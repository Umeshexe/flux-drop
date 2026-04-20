# FluxDrop - Real-Time File Sharing

FluxDrop is a mobile application developed for the NeoSapien Developer Intern Assessment. It is built with Flutter and Firebase, featuring a custom implementation of the CRED NeoPOP design system.

## 🏃‍♂️ How to Run Locally
The app relies on Firebase (Firestore, Storage, FCM) as its relay and signaling server. 

1. Ensure you have Flutter installed (`flutter doctor`).
2. Clone this repository.
3. Run `flutter pub get`.
4. (Optional) The project is already hooked up to a dev Firebase project via `firebase_options.dart`. To use your own, run `flutterfire configure`.
5. Run using `flutter run` on a physical device (Emulators do not properly support the FCM push notification pipeline without Google Play Services setup).

## 📱 Devices & OS Tested On
- Physical iPhone 13 Pro Max (iOS 17+)
- Android Emulator API 34 & Physical Android device

## 🏗 Architecture Overview
```text
  [ Sender Device ]                      [ Receiver Device ]
    (Flutter App)                          (Flutter App)
          |                                      ^
          | 1. Create Transfer                   | 4. Snapshot Listener
          v                                      |    (UI Updates)
  +------------------+                   +------------------+
  |    Firestore     | <--- 3. Notify -- |       FCM        |
  |  (State, Sync)   |                   |  (Push / Wakeup) |
  +------------------+                   +------------------+
          ^                                      |
          | 2. Upload Bytes                      | 5. Download Bytes
          v                                      v
  +---------------------------------------------------------+
  |                   Firebase Storage                      |
  |                   (The Media Relay)                     |
  +---------------------------------------------------------+
```
- **Client**: Flutter with the `neopop` package for high-fidelity UI switching. 
- **Transport & Relay**: Firebase Storage handles the heavy payload lifting. Firestore handles the real-time state machine (uploading, ready, downloading, completed, rejected). FCM is used to wake up the receiver when a transfer starts.
- **Storage**: Native platform channels handle writing to disk.

## 📡 Transport Choice & Rationale
**Chosen Transport:** Firebase (Firestore Listeners + Firebase Storage).

**Rationale:** The brief demanded transfers work across *distance, different networks, NATs, and countries*. While WebRTC is great for local P2P, establishing robust cross-world WebRTC connections requires deploying and maintaining dedicated TURN servers to punch through symmetric NATs. Firebase Storage provides a rock-solid, globally distributed relay out of the box. The Firebase SDK natively handles network drops, chunked resumable uploads, and TLS transport encryption without reinventing the wheel. Firestore snapshot listeners trivially satisfy the "real-time progress without manual refresh" requirement with very low overhead. 

## 🛠 Platform Channel Bonus (Option #2)
I chose to implement **Option #2: Save-to-gallery / Downloads**. 

Rather than relying on pub.dev packages like `image_gallery_saver`, I implemented a custom MethodChannel (`fluxdrop/storage`):
* **Android** (`MainActivity.kt`): Writes received media to the `MediaStore` for Android 10+ scoped storage compliance. It creates an `IS_PENDING` item, streams the bytes out of process, and commits it securely to the `Pictures/FluxDrop` or `Movies/FluxDrop` album without needing MANAGE_EXTERNAL_STORAGE permission.
* **iOS** (`AppDelegate.swift`): Uses `PHPhotoLibrary` to request `.addOnly` access, executing `PHAssetChangeRequest` blocks to push downloaded videos and images straight into the native camera roll.

*(Note: For the file picker portion, the app uses standard `file_picker` as the prompt requested we pick exactly one bonus channel to implement).*

## 🛡 Edge Cases Handled
✅ **Short-code collisions:** Short-codes are assigned using Firebase logic, ensuring unique mappings upon local identity provision.
✅ **Invalid recipient code:** Sender gets immediate visual "Not Found" UI feedback before any upload starts.
✅ **Recipient offline:** The transfer creates a Firestore document with a 24-hour TTL (`expiresAt`). If the receiver is offline, the FCM notification is queued. If they open the app within 24 hours, the transfer is waiting for them.
✅ **Metered connections & Large files:** The app warns users if a payload is large. Memory exhaustion (OOM) is avoided by streaming bytes to the disk during download rather than buffering into RAM.
✅ **Network drops mid-transfer:** Firebase SDK handles TCP disconnects gracefully; chunked resumable uploads allow the transfer to survive flaky connections.
✅ **Permission denial:** The app degrades gracefully. If Storage/Photos permissions are denied, it falls back to app-internal documents dir with a Toast.
✅ **Transport & Content Privacy:** All relay traffic goes over TLS (Firebase default). The receiver UI features a strict **Accept/Decline** gate on the Home screen. Files are NEVER automatically downloaded to the recipient's phone without their explicit tap.

## ⚠️ Known Bugs & Limitations (Honesty Section)
* **True Process Backgrounding:** While FCM push notifications wake the background isolate, true "survive in the deep background for 15 minutes" downloading is constrained by OEM battery killers (Xiaomi, Samsung) and iOS URLSession limits. An upload process killed completely by the OS (OOM kill) will not auto-resume upon cold boot; the user must manually hit "Download Again."
* **Simultaneous Identical Transers:** Duplicate file delivery is deduped by transfer ID, but if two senders happen to send the exact same file hash simultaneously, the app doesn't perform server-side deduplication mapping (the relay stores two copies).
* **Cross-Platform Parity Details:** iOS Push Notifications (APNs) require a paid Apple Developer Program entitlement. Because of this, offline push notifications on physical iOS devices will not trigger if built with a free dev cert, though the real-time Firestore listeners work perfectly when the app is in the foreground.

## 🤖 AI Tool Usage
I utilized Claude, Gemini, and Cursor heavily to accelerate the build.
* **Where it helped:** Scaffolded the `FluxButton` and `FluxSurface` wrapper widgets to adapt the official CRED NeoPOP package cleanly. It also helped write the Android `MediaStore` Kotlin boilerplate which is notoriously verbose.
* **Where I overrode it:** 
  1. The AI initially attempted to handle the PDF's requirement of "UX under failure / Clear success & failure states" by keeping cancelled downloads permanently locked in a "failed" state. I re-architected `transfer_service.dart` to compute the correct `revertStatus` so that historical transfers cleanly revert to `completed` rather than spamming the user with new Accept/Decline popups.
  2. The AI missed the terminology consistency between the home screen's "Accept" and the transfer screen's "Download" first-time actions. I manually aligned these to enforce the privacy gate requirement properly.
