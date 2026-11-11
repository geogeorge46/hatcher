package com.hatcher.app.escalation

import android.util.Log

/**
 * EscalationService — Phase 2 hook.
 *
 * In Phase 2, this service will:
 * - Send Telegram bot messages when a rotation is missed by all phones
 * - Trigger SMS/phone calls via gateway
 * - Coordinate server-side escalation via Cloud Functions
 *
 * Phase 1: not implemented. The interface is defined here so Phase 2
 * can plug in without refactoring the alarm or Firestore layer.
 *
 * Usage (Phase 1):
 *   val svc = EscalationService.current()
 *   svc.escalateMissed("2024-11-10", "morning")  // no-op in Phase 1
 *
 * Usage (Phase 2 — swap implementation):
 *   // In your DI setup:
 *   EscalationService.setImplementation(TelegramEscalationService(...))
 */
interface EscalationService {

    /**
     * Called when every phone in the household missed a rotation slot.
     *
     * @param date  ISO-8601 date string, e.g. "2024-11-10"
     * @param slot  One of "morning", "noon", or "evening"
     *
     * Phase 2 behaviour: sends a Telegram message and/or SMS to escalation
     * contacts, then logs the escalation to Firestore for auditing.
     */
    suspend fun escalateMissed(date: String, slot: String)

    /**
     * Called when a humidity reading is out of acceptable range for the given
     * incubation day.
     *
     * @param day  Current incubation day (1–21)
     *
     * Phase 2 behaviour: sends an urgent Telegram/SMS alert with the current
     * reading and acceptable range for that day.
     */
    suspend fun notifyHumidity(day: Int)

    /**
     * Cancels a previously escalated missed-rotation alert (e.g., because a
     * user just tapped "Rotated ✔" very late).
     *
     * @param date  ISO-8601 date string, e.g. "2024-11-10"
     * @param slot  One of "morning", "noon", or "evening"
     *
     * Phase 2 behaviour: sends a "never mind" follow-up message and marks the
     * Firestore escalation document as resolved.
     */
    suspend fun cancelEscalation(date: String, slot: String)

    // ─────────────────────────────────────────────────────────────────────────
    companion object {
        /** The active implementation. Defaults to [NoOpEscalationService]. */
        @Volatile
        private var impl: EscalationService = NoOpEscalationService()

        /**
         * Returns the current [EscalationService] implementation.
         * Phase 1 returns [NoOpEscalationService]. Phase 2 will return a real
         * implementation set via [setImplementation].
         */
        fun current(): EscalationService = impl

        /**
         * Swaps the active implementation.
         * Call this during app initialisation when Phase 2 is enabled:
         *
         *   EscalationService.setImplementation(TelegramEscalationService(botToken, chatId))
         */
        fun setImplementation(service: EscalationService) {
            impl = service
            Log.i("Hatcher.EscalationSvc", "Implementation set to ${service::class.simpleName}")
        }
    }
}

/**
 * NoOpEscalationService — Phase 1 stub.
 *
 * All methods are intentional no-ops. They log at DEBUG level so that
 * developer builds can confirm the calls are being made without any
 * side-effects.
 *
 * This class will be replaced in Phase 2 by a concrete implementation
 * (e.g., TelegramEscalationService) without changing any call sites.
 */
class NoOpEscalationService : EscalationService {

    private val tag = "Hatcher.NoOpEscalation"

    override suspend fun escalateMissed(date: String, slot: String) {
        // Phase 1: intentional no-op.
        // Phase 2: post Telegram message, trigger SMS gateway, log to Firestore.
        Log.d(tag, "escalateMissed(date=$date, slot=$slot) — no-op in Phase 1")
    }

    override suspend fun notifyHumidity(day: Int) {
        // Phase 1: intentional no-op.
        // Phase 2: send urgent humidity alert via Telegram/SMS.
        Log.d(tag, "notifyHumidity(day=$day) — no-op in Phase 1")
    }

    override suspend fun cancelEscalation(date: String, slot: String) {
        // Phase 1: intentional no-op.
        // Phase 2: resolve the Firestore escalation doc and send a follow-up.
        Log.d(tag, "cancelEscalation(date=$date, slot=$slot) — no-op in Phase 1")
    }
}
