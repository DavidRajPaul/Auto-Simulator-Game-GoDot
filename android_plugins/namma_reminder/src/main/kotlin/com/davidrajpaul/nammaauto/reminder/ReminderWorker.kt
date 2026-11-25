package com.davidrajpaul.nammaauto.reminder

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/** Runs once when a scheduled reminder is due (WorkManager keeps it across reboots) and posts it. */
class ReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
	override fun doWork(): Result {
		val title = inputData.getString(Reminders.KEY_TITLE)
		val body = inputData.getString(Reminders.KEY_BODY)
		if (title != null && body != null) {
			// Jobs queued by an older build carry no look / chip / action: they show the street card.
			Reminders.show(
				applicationContext, inputData.getInt(Reminders.KEY_ID, 1), title, body,
				inputData.getString(Reminders.KEY_LOOK),
				inputData.getString(Reminders.KEY_CHIP) ?: "",
				inputData.getString(Reminders.KEY_ACTION) ?: "",
			)
		}
		return Result.success()
	}
}
