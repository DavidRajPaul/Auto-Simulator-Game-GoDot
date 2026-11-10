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
			Reminders.show(applicationContext, inputData.getInt(Reminders.KEY_ID, 1), title, body)
		}
		return Result.success()
	}
}
