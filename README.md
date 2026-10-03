# FluxDrop

FluxDrop is a mobile-only file sharing app.

It lets one phone send files to another phone using a short code, with Firebase handling relay/signaling over the internet and a local LAN fast-path available in the codebase for nearby devices on the same Wi‑Fi subnet.

The goal for this submission was not to build the most feature-rich app possible. The goal was to build a real, demoable mobile transfer flow, handle the starred edge cases honestly, and leave a codebase that I can defend in a review.

## What Works

- Anonymous onboarding with local identity provisioning on first launch
- 6-character short-code identity with collision retry logic
- Send one or more files to another device by short code
- Real-time sender/receiver progress using Firestore listeners + Firebase Storage tasks
- Cloud relay over the internet using Firebase Storage signed downloads
- Incoming transfer notifications on Android when the app is closed
- Accept / decline flow for first-time incoming downloads
- Download cancellation and upload cancellation
- Re-download completed transfers
- SHA-256 integrity verification after download
- Native save-to-gallery / save-to-photos support through platform channels
- Metered connection warning for large transfers
- Low-storage pre-check through native platform channels
- Duplicate download protection by transfer ID
- App restart recovery for stale transfer documents
- Optional NeoPOP visual mode using the official CRED `neopop` Flutter package

## Devices & OS Versions Tested

Primary tested flows:

- Android physical device: `CPH2569` on Android 15
- iPhone physical device: iPhone 13 Pro Max on iOS 26.4.1

Flows I personally tested during development:

- Android -> Android over Firebase relay
- iPhone -> Android over Firebase relay
- Android receiver closed -> Android push notification tap routing
- Transfer cancel / retry / accept / decline flows
- Save to Photos on iOS
- Save to Gallery / scoped storage path on Android code path

Notes:

- The Android side was the primary target for closed-app push and review/demo reliability.
- iOS foreground app flow works, but true closed-app push behavior on iOS depends on APNs entitlements and signing setup.

## How to Run Locally

### Prerequisites

- Flutter SDK installed and working in `flutter doctor`
- Xcode for iOS builds
- Android Studio / Android SDK for Android builds
- Firebase CLI only if you want to redeploy the included Cloud Function

### App Setup

1. Clone the repo.
2. Run `flutter pub get`.
3. Make sure Firebase config files are present:
   - `lib/firebase_options.dart`
   - Android `google-services.json`
   - iOS `GoogleService-Info.plist`
4. Run on a physical device:
   - `flutter run`

### Backend / Firebase Setup

This app expects the following Firebase services:

- Firestore
- Firebase Storage
- Firebase Cloud Messaging
- Cloud Functions

If you want to use your own Firebase project instead of the one currently wired during development:

1. Run `flutterfire configure`
2. Update platform Firebase config files
3. Deploy the Cloud Function in `functions/`

### Cloud Function Deployment

The repo contains a Firebase Cloud Function used to notify the receiver when a transfer becomes ready:

- `functions/index.js`

Deploy it with:

```bash
firebase deploy --only functions --project <your-project-id>
```

## Installable Build Notes

### Android

For submission, generate a signed debug APK:

```bash
flutter build apk --debug
```

Recommended verification:

- uninstall the app from the target device
- install the generated APK fresh
- verify onboarding, send, receive, accept, cancel, and notification tap behavior

### iOS

For this submission, iOS is best treated as:

- a real-device run target from Xcode / `flutter run`
- not the primary reviewed platform for closed-app push behavior

If shipping to a reviewer on iOS, include exact Xcode run instructions unless you have TestFlight/APNs-ready signing.

Debug-run caveat from my local setup:

- on my local iPhone debug setup, `flutter run` would occasionally fail during launch with a native `EXC_BAD_ACCESS` crash on a Dart worker thread before the app fully opened
- in practice, stopping and re-running `flutter run` 2-3 times usually cleared it and the app launched normally
- I was not able to prove a single root cause with confidence, but it appeared related to local iOS debug/runtime initialization rather than the normal in-app transfer flow once the app was running
- if reviewed using a properly provisioned Apple Developer account / signing setup, I would still recommend treating Android as the primary demo path and iOS as a secondary verified path

## Architecture Overview

```text
  [ Sender App ]
        |
        | 1. Create / update transfer doc
        v
  +--------------------+
  |     Firestore      |
  | transfer state     |
  +--------------------+
        |
        | 2. Upload file bytes
        v
  +--------------------+
  | Firebase Storage   |
  | cloud relay        |
  +--------------------+
        |
        | 3. Receiver downloads
        v
  [ Receiver App ]

  Notification side-path:
  Firestore status change -> Cloud Function -> FCM -> receiver opens Transfers
```

### Main Pieces

- UI: Flutter screens and widgets
- State / signaling: Firestore transfer documents
- File relay: Firebase Storage
- Notifications: Cloud Function + FCM
- Native bridge: MethodChannel for storage checks and save-to-gallery/photos
- Optional nearby path: LAN TCP transfer service for same-subnet devices

## Transport Choice and Rationale

I used Firebase as the primary transport stack:

- Firestore for state machine updates
- Firebase Storage for file relay
- FCM for closed-app awareness on Android

Why I chose this:

- it works across distance and NAT without me running my own relay infrastructure
- Firebase Storage already handles chunked uploads well for large files
- Firestore listeners are enough to achieve the "recipient sees it within a couple of seconds" expectation
- it let me focus time on mobile behavior, edge cases, and transfer UX instead of building and hosting a custom backend

Why not WebRTC as the primary path:

- for internet-grade reliability, WebRTC usually means STUN/TURN work and more debugging around NAT traversal
- that would have been higher risk for the assessment timeline

### Nearby / LAN Fast-Path

There is also a LAN fast-path implementation in the codebase:

- sender can open a local TCP server
- receiver can connect directly if both devices are on the same `/24` subnet
- files can stream peer-to-peer without Firebase Storage for the payload itself

Important honesty note:

- this path is implemented in the repo and integrated into the transfer service
- the cloud relay path was the primary tested and demo-safe path
- I would describe the LAN path as implemented but still something I would re-verify carefully before relying on it for the final demo

Relevant files:

- [transfer_service.dart](/Users/umesh/Desktop/NeoSapien/fluxdrop/lib/services/transfer_service.dart)
- [lan_transfer_service.dart](/Users/umesh/Desktop/NeoSapien/fluxdrop/lib/services/lan_transfer_service.dart)

## Platform Channel Bonus Work

I attempted bonus platform channel work instead of relying only on pub.dev packages.

### Implemented

1. Save to gallery / photos

- Android: native `MediaStore` path via Kotlin
- iOS: native `PHPhotoLibrary` path via Swift
- exposed to Flutter through `MethodChannel('fluxdrop/storage')`

2. Native low-storage check

- Android: storage space checked natively before accepting a large download
- iOS: free-space check exposed through the same channel

3. Nearby transport support

- Android native Wi‑Fi IP lookup is used to improve local subnet detection

Relevant files:

- [MainActivity.kt](/Users/umesh/Desktop/NeoSapien/fluxdrop/android/app/src/main/kotlin/com/example/fluxdrop/MainActivity.kt)
- [AppDelegate.swift](/Users/umesh/Desktop/NeoSapien/fluxdrop/ios/Runner/AppDelegate.swift)

### Not Implemented

- background transfer survival via Android foreground service / iOS `URLSession`
- native file picker through direct platform APIs
- native share sheet as a custom channel feature

## Section 3 Edge Cases

### Handled

- ★ Short-code collisions
  - generated code retries until unique
- ★ Invalid recipient code
  - sender gets immediate validation / "not found" feedback
- Ambiguous characters
  - alphabet intentionally avoids ambiguous characters
- Self-send
  - blocked
- ★ Recipient offline
  - queue-with-TTL approach
  - transfer stays available until expiry
- ★ Network drops mid-transfer
  - Firebase Storage handles upload retry behavior better than a naive in-memory approach
- Duplicate delivery
  - tracked by transfer ID, not filename
- Metered connections
  - warning shown before large transfers on likely metered connection
- ★ Large files
  - capped at 500 MB
  - upload uses `putFile`
  - download streams to disk
- ★ Multiple files at once
  - batch transfer works
  - one failure does not kill the whole batch
- Unusual MIME types
  - unknown types fall back to `application/octet-stream`
- Empty / zero-byte files
  - blocked before sending
- Filename conflicts on save
  - renamed automatically with suffix
- Corrupted transfers
  - SHA-256 checked after download
- ★ Permission denial
  - app degrades instead of crashing
- Scoped storage
  - Android save-to-gallery uses `MediaStore`
- ★ Incoming transfer while app is closed
  - Android push notification flow implemented
- Low device storage
  - native free-space pre-check before download
- ★ Transport encryption
  - Firebase network path uses TLS
- UX cancel affordance
  - long-running upload/download operations can be cancelled
- Clear error messaging
  - failures are surfaced through toasts / visible states rather than silent crashes
- State survival after app death
  - stale transfer recovery runs on startup

### Partially Handled / Important Caveats

- Sender kills app mid-upload
  - transfer does not continue in the true background
  - stale upload is cleaned up on next app launch
- App killed by OS under memory pressure
  - recovery logic exists, but this is not the same as true background continuation
- Network transitions / airplane mode / long backgrounding
  - basic recovery is there through Firebase task behavior and restart cleanup
  - not fully production-hardened for every mobile OS edge case
- Content privacy
  - receiver has accept/decline flow
  - there is no block list or rate limiting yet
- At-rest encryption on relay
  - I rely on Firebase-managed infrastructure
  - I did not add an app-level custom encryption layer on top of Firebase Storage

### Not Fully Solved

- True background transfer survival
- Full iOS closed-app push verification in this local signing environment
- OEM battery killer mitigation
- Account recovery after app data clear on Android
- LAN path encryption

## Known Bugs / Limitations

- iOS push is not the strongest part of this submission because APNs-ready signing was not available in my local setup
- iOS debug launches were occasionally flaky in my local environment and sometimes required restarting `flutter run` a couple of times before the app opened successfully
- the LAN fast-path is implemented, but the Firebase relay path is the one I would treat as primary for demo confidence
- background continuation is not implemented as a full native worker/service solution
- the app supports re-downloads, but I intentionally kept the state model simple instead of building a more complex download history manager
- cross-platform parity exists, but Android is the safer primary demo target

## AI Tool Usage

I used AI tools as pair-programming assistance, not as a substitute for understanding the code.

Tools used:

- Codex
- Gemini

Where AI helped most:

- platform channel boilerplate
- Firebase plumbing
- UI refactors
- edge-case brainstorming
- repetitive code cleanup

Where I overrode AI suggestions:

- transfer state transitions around cancel / retry / re-download
- notification tap routing and platform-specific behavior
- parts of the NeoPOP integration where the initial changes affected the wrong UI surfaces

## Repo Notes

- No runtime `.env` values are required for the current local setup
- Firebase configuration is handled through checked-in platform config files / `firebase_options.dart`
- A placeholder `.env.example` is included only to satisfy fresh-clone/documentation expectations

## Fresh Clone Checklist

On a fresh machine, I would expect someone reviewing the repo to do this:

1. `flutter pub get`
2. confirm Firebase config files are present
3. optionally deploy `functions/` to their own Firebase project
4. run on a physical Android device
5. test:
   - onboarding
   - short-code lookup
   - send file
   - receive file
   - accept / decline
   - cancel transfer
   - notification tap routing

## Final Honesty Summary

What I am most confident showing live:

- anonymous onboarding
- short-code identity
- Android-to-Android or iPhone-to-Android file transfer
- real-time progress
- accept / decline
- cancel / retry
- Android closed-app incoming transfer notification
- save-to-gallery / save-to-photos integration

What I would call out explicitly in the walkthrough instead of overselling:

- iOS closed-app push is limited by local signing / APNs setup
- background survival is not fully implemented
- LAN fast-path exists in the codebase, but Firebase relay is the primary reliable path
