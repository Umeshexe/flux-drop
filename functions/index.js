const functions = require("firebase-functions");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

admin.initializeApp();

exports.notifyTransferReady = functions.firestore
  .document("transfers/{transferId}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) {
      return null;
    }

    const statusChanged = before?.status !== after.status;
    const shouldNotify = after.status === "uploaded" && statusChanged;

    if (!shouldNotify || !after.receiverId) {
      return null;
    }

    const receiverDoc = await admin
      .firestore()
      .collection("users")
      .doc(after.receiverId)
      .get();

    const receiver = receiverDoc.data();
    const token = receiver?.fcmToken;
    if (!token) {
      logger.info("Receiver has no FCM token", {
        receiverId: after.receiverId,
        transferId: after.transferId,
      });
      return null;
    }

    const senderCode = after.senderCode || "Someone";
    const transferId = after.transferId || context.params.transferId;

    await admin.messaging().send({
      token,
      // data block: used by foreground handler in Flutter
      data: {
        title: `${senderCode} sent you file(s)`,
        body: `Tap to download — ready in FluxDrop`,
        transferId,
      },
      // Android: explicit notification block required for closed-app display
      android: {
        priority: "high",
        notification: {
          title: `📥 ${senderCode} sent you file(s)`,
          body: "Tap to open FluxDrop and download",
          channelId: "fluxdrop_transfers",
          sound: "default",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      // iOS: APNS payload for closed-app display
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            alert: {
              title: `📥 ${senderCode} sent you file(s)`,
              body: "Tap to open FluxDrop and download",
            },
            sound: "default",
            badge: 1,
          },
        },
      },
    });
        
    return null;
  });
