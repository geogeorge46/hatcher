package com.hatcher.app.escalation

import android.util.Log
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * FirestoreEscalationService — Phase 2 implementation of EscalationService.
 *
 * Cloud Functions (`escalationTick`) drive the scheduled ladder on the server,
 * while this client-side service resolves/cancels escalation state or logs
 * manual events directly into Firestore.
 */
class FirestoreEscalationService(
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance()
) : EscalationService {

    companion object {
        private const val TAG = "Hatcher.FirestoreEsc"
    }

    override suspend fun escalateMissed(date: String, slot: String) {
        Log.i(TAG, "Marking slot missed in Firestore escalation doc: ${date}_${slot}")
        try {
            db.collection("escalations").document("${date}_${slot}")
                .set(
                    mapOf(
                        "date" to date,
                        "slot" to slot,
                        "status" to "missed",
                        "updatedAt" to Timestamp.now()
                    )
                ).await()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to escalateMissed: ${e.message}")
        }
    }

    override suspend fun notifyHumidity(day: Int) {
        val nowMs = System.currentTimeMillis()
        try {
            db.collection("auditLogs").add(
                mapOf(
                    "timestamp" to Timestamp.now(),
                    "createdAtMs" to nowMs,
                    "expiresAt" to Timestamp(Date(nowMs + 30L * 24 * 60 * 60 * 1000)),
                    "date" to "day_$day",
                    "slotKey" to "lockdown",
                    "channel" to "system",
                    "targetName" to "All",
                    "result" to "humidity_reminder",
                    "details" to "Day $day lockdown humidity reminder triggered"
                )
            ).await()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to log humidity reminder: ${e.message}")
        }
    }

    override suspend fun cancelEscalation(date: String, slot: String) {
        Log.i(TAG, "Resolving escalation doc: ${date}_${slot}")
        try {
            db.collection("escalations").document("${date}_${slot}")
                .update(
                    mapOf(
                        "status" to "done",
                        "updatedAt" to Timestamp.now()
                    )
                ).await()
        } catch (e: Exception) {
            Log.d(TAG, "No escalation doc to cancel or offline: ${e.message}")
        }
    }
}
