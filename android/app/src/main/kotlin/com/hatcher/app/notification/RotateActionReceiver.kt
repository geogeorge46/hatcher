package com.hatcher.app.notification

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.hatcher.app.MainActivity
import com.hatcher.app.alarm.AlarmService

/**
 * RotateActionReceiver handles the "Rotated ✔" action directly from notifications
 * without needing to launch the Flutter UI.
 *
 * It:
 * 1. Writes the rotation doc to Cloud Firestore (rotations/{date}_{slot})
 * 2. Marks the slot done in local SharedPreferences immediately
 * 3. Broadcasts ACTION_ROTATION_DONE to stop the ringing AlarmService
 * 4. Cancels the alarm notification
 */
class RotateActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "RotateActionReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val slotKey = intent.getStringExtra("slotKey") ?: return
        val date = intent.getStringExtra("date") ?: return

        Log.i(TAG, "User logged rotation from notification: $slotKey on $date")

        val prefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val doneBy = prefs.getString("user_name", "Unknown") ?: "Unknown"
        val uid = FirebaseAuth.getInstance().currentUser?.uid
            ?: prefs.getString("user_uid", "anonymous") ?: "anonymous"
        val batchId = prefs.getString("current_batch_id", "") ?: ""

        // 1. Mark in local SharedPreferences immediately so local checks pass
        prefs.edit().putBoolean("done_${date}_${slotKey}", true).apply()

        // 2. Stop the AlarmService
        val stopIntent = Intent(AlarmService.ACTION_ROTATION_DONE).apply {
            setPackage(context.packageName)
            putExtra("slotKey", slotKey)
            putExtra("date", date)
        }
        context.sendBroadcast(stopIntent)

        // 3. Dismiss notifications
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID)
        notificationManager.cancel(AlarmService.FOREGROUND_NOTIFICATION_ID + 1)

        // 4. Save to Firestore (top-level collection: rotations/{date}_{slot})
        val docId = "${date}_${slotKey}"
        val rotationData = hashMapOf(
            "date" to date,
            "slot" to slotKey,
            "doneBy" to doneBy,
            "doneByUid" to uid,
            "batchId" to batchId,
            "doneAt" to Timestamp.now()
        )

        try {
            val db = FirebaseFirestore.getInstance()
            val docRef = db.collection("rotations").document(docId)

            // Transaction / atomic create to follow first-tap-wins
            db.runTransaction { tx ->
                val snapshot = tx.get(docRef)
                if (!snapshot.exists()) {
                    tx.set(docRef, rotationData)
                }
                null
            }.addOnSuccessListener {
                Log.i(TAG, "Rotation successfully written to Firestore for $docId")
            }.addOnFailureListener { e ->
                Log.w(TAG, "Failed to write rotation to Firestore (offline or conflict): ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initiating Firestore write from receiver", e)
        }

        Toast.makeText(context, "രേഖപ്പെടുത്തി: $doneBy ✔", Toast.LENGTH_SHORT).show()
    }
}
