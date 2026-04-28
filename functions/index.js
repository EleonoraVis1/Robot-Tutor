/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
const admin = require("firebase-admin");
admin.initializeApp();

const { onDocumentCreated } = require("firebase-functions/v2/firestore");

exports.sendInviteNotification = onDocumentCreated(
  "user_profiles/{studentId}/invites/{inviteId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const invite = snap.data();
    const studentId = event.params.studentId;

    const studentDoc = await admin.firestore()
      .collection("user_profiles")
      .doc(studentId)
      .get();

    const studentData = studentDoc.data();

    if (!studentData?.fcmToken) return;

    await admin.messaging().send({
      token: studentData.fcmToken,
      notification: {
        title: "New Invite",
        body: `${invite.supervisorFullName} wants to be your supervisor`,
      },
    });
  }
);

exports.sendSupervisorNotification = onDocumentCreated(
  "user_profiles/{supervisorUid}/notifications/{notifId}",
  async (event) => {
    const notif = event.data?.data();
    const supervisorUid = event.params.supervisorUid;

    if (!notif) return;

    console.log("Supervisor notification triggered");

    const supervisorDoc = await admin.firestore()
      .collection("user_profiles")
      .doc(supervisorUid)
      .get();

    const supervisorData = supervisorDoc.data();

    if (!supervisorData?.fcmToken) {
      console.log("No FCM token for supervisor");
      return;
    }

    let body = "";

    if (notif.type === "quiz") {
      const action =
        notif.status === "retook"
          ? "retook"
          : "completed";

      const subject = notif.subjectId || "Subject";
      const grade = notif.grade ? `Grade ${notif.grade}` : "";
      const chapter = notif.chapter ? `Chapter ${notif.chapter}` : "";
      const module = notif.moduleTitle || notif.moduleId || "";

      body = `${notif.studentName} ${action} ${grade} ${subject} – ${chapter}: ${module}`;
    }

    else {
      const action = (notif.status || "").toLowerCase();

      body = `${notif.studentName} ${action} your invite`;
    }

    const payload = {
      token: supervisorData.fcmToken,
      notification: {
        title: "Student Update",
        body: body,
      },
    };

    await admin.messaging().send(payload);
  }
);
