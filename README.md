# FluxDrop

Built for the NeoSapien Developer Intern Assessment. A real-time cross-device file sharing app using Flutter and Firebase, featuring the CRED NeoPOP design system.

## How to Run Locally
FluxDrop relies on Firebase (Firestore, Storage, FCM) for signaling and cloud relay.

1. Ensure you have Flutter installed (`flutter doctor`).
2. Clone this repository.
3. Run `flutter pub get`.
4. (Optional) The project is already hooked up to a dev Firebase project via `firebase_options.dart`. To use your own, run `flutterfire configure`.
5. Run using `flutter run` on a physical device. Note: Emulators don't handle FCM push notifications properly without Google Play Services setup.

## Devices & OS Tested On
- iPhone 13 Pro Max (Physical device, iOS 26.4.1)
- Android API 34 (Emulator) & Physical Android device

## Backend & Architecture Strategy
```text
  [ Sender App ]                         [ Receiver App ]
         |                                      ^
         | 1. Create Transfer                   | 4. Snapshot Listener
         v                                      |    
 +------------------+                   +------------------+
 |    Firestore     | <--- 3. Notify -- |       FCM        |
 |  (State machine) |                   |  (Push / Wakeup) |
 +------------------+                   +------------------+
         ^                                      |
         | 2. Upload Bytes                      | 5. Download Bytes
         v                                      v
 +---------------------------------------------------------+
 |                   Firebase Storage                      |
 |                   (Cloud Relay)                         |
 +---------------------------------------------------------+
 ```

I chose a **Backend-as-a-Service (BaaS) approach** over writing a custom Node.js/Go backend to focus entirely on the mobile experience while ensuring stability.

### 1. Cloud Relay (Remote Transfers)
- **State & Signaling -> Firestore:** Instead of building a custom WebSocket server, I used Firestore. The `transfers` collection acts as a pure state machine (`uploading`, `ready`, `downloading`, `completed`, `failed`). B's app runs a snapshot listener for `receiverId == B`. This provides near-instant synchronization without manual polling.
- **Payload Transport -> Firebase Storage:** The sender pushes chunked bytes to Firebase Storage. **Why not WebRTC?** Because true Remote WebRTC across symmetric NATs requires deploying and maintaining dedicated TURN servers. Firebase Storage provides a rock-solid, chunked, automatically-resumable global relay out of the box with zero ops overhead.

### 2. Nearby Transport Fast-Path (Option #5)
When A and B are on the exact same Wi-Fi subnet, they bypass Firebase Storage entirely:
1. Sender A spins up a raw `ServerSocket` and advertises its LAN IP/Port in the Firestore signaling doc.
2. Receiver B sees the IP, confirms they are on the same `/24` subnet, and connects directly via TCP.
3. The raw binary payload traverses the local router (skipping the internet).

## Platform Channel Bonus Work
I tackled **Option #2 (Save-to-gallery)** and elements of **Option #5 (Nearby Transport)**:

1. **MediaStore & Photos (Option #2)**: Built a custom `fluxdrop/storage` MethodChannel. 
   - **Android**: Custom Kotlin writes media directly into `MediaStore` (Scoped Storage compliance), directing files into `Pictures/FluxDrop` or `Movies/FluxDrop` without needing the heavy `MANAGE_EXTERNAL_STORAGE` permission.
   - **iOS**: Uses `PHPhotoLibrary` to push images and videos natively into the camera roll.
2. **Local IP Discovery (Option #5)**: To facilitate the LAN fast-path, the Android side natively fetches the real Wi-Fi IP address directly via `WifiManager`, because dart:io's `NetworkInterface` is notoriously unreliable on recent Android API levels.

## Edge Cases Handled (Section 3)

- **★ Short-code collisions**: Handled securely via Firebase transaction logic during on-device provisioning.
- **★ Invalid recipient code**: Sender gets an immediate "Not Found" UI validation before attempting any upload.
- **★ Recipient offline**: The transfer creates a Firestore document with a 24-hour TTL (`expiresAt`). If the receiver opens the app later, the transfer will be waiting to be accepted.
- **★ Network drops mid-transfer**: Handled automatically by the Firebase SDK using chunked uploads and retries.
- **★ Large files**: Capped at 500 MB. We stream bytes directly to disk via `writeToFile` (and chunked TCP socket reading for LAN) to prevent out-of-memory (OOM) crashes.
- **★ Multiple files at once**: Batch sending works. Adding duplicate files highlights them clearly with an amber badge in the UI.
- **★ Permission denial**: Graceful degradation. If Android 13+ media permissions are denied, it falls back to saving in the app's internal documents folder.
- **★ Incoming transfer while app is closed**: Handled by FCM. Background pushes deep-link the user back into the transfers view.
- **★ Transport encryption**: Firebase Storage path enforces TLS 1.3 natively. 
- **Corrupted transfers**: SHA-256 hashes are computed dynamically on upload and verified on download across both cloud and local TCP paths. Mismatches delete the file and throw an error.
- **App killed mid-transfer**: Implemented a startup scanner (`recoverStaleTransfers`). It detects orphaned "uploading" or "downloading" documents left by crashes/force-quits and cleans them up gracefully (failing the stuck upload to alert the receiver, or reverting a stuck download so the receiver can tap 'Accept' again).

## Scope & Honesty Section (What I Didn't Do)
In accordance with the assessment's emphasis on scope discipline, here is what is skipped or limited:

1. **Background Survival (Option #4)**: True background download survival via iOS `URLSession` / Android Foreground Services is not implemented. OEM battery killers make this extremely complex. Instead of faking it or shipping a flaky version, I focused entirely on stability and built the `recoverStaleTransfers()` logic above. If the OS kills the app due to memory pressure mid-download, the transfer simply reverts to "uploaded" securely on next launch.
2. **Cross-Platform Push Constraints**: The code wraps FCM perfectly, but testing true offline background pushes on an iOS physical device requires a paid Apple Developer certificate (APNs entitlement), which I do not have on this machine. Foreground Firestore listeners work instantly.
3. **Identity Persistence / Recovery**: The anonymous local UID and short-code persist as long as the app is installed. If a user clears App Data or reinstalls, they get a new code. There is no account recovery flow. This is intentional to respect the "anonymous onboarding" requirement effortlessly.
4. **LAN Encryption**: The cloud path (Firebase) enforces TLS 1.3 natively. The local Wi-Fi TCP fast-path is unencrypted. It relies on the inherent security of the private WPA2/WPA3 subnet (like Airdrop over local Wi-Fi), but theoretically is sniffable by a bad actor sitting on the same local network.

## AI Tool Usage
I utilized Claude, Gemini, and Cursor as pair programming partners for this assessment.

- **Where it helped**: Massively accelerated writing the Android `MediaStore` Kotlin boilerplate (which is famously verbose and unforgiving), and quickly scaffolding wrappers around the CRED NeoPOP package components.
- **Where I overrode it**: 
  1. AI initially suggested keeping interrupted downloads in a permanent "failed" state. I re-architected the state machine's error handler to compute a `revertStatus`, allowing interrupted downloads to gracefully revert to "uploaded" so a user can simply tap "Accept" and try again.
  2. The AI attempted to replace selected files entirely when adding more files in the sender UI. I stepped in and rewrote the logic to correctly append the files while adding deduplication and duplication-highlighting logic.
