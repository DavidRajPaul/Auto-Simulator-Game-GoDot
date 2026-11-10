package com.davidrajpaul.nammaauto.reminder

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar

/** Channel, timing and posting helpers shared by the plugin (scheduling) and the worker (posting). */
internal object Reminders {
	const val TAG = "namma_reminder"
	const val CHANNEL_ID = "namma_daily_reminder"
	const val PREFS = "namma_reminder"
	const val KEY_ID = "id"
	const val KEY_TITLE = "title"
	const val KEY_BODY = "body"

	/** Brand yellow (UIKit.YELLOW) for the small icon's accent. */
	private const val ACCENT = 0xFFFFC21A.toInt()

	/** False when the player denied POST_NOTIFICATIONS (Android 13+) or switched the app's notifications off. */
	fun enabled(ctx: Context): Boolean = NotificationManagerCompat.from(ctx).areNotificationsEnabled()

	/**
	 * Milliseconds from [nowMs] until [hour]:00 on the day [daysAhead] days after today, in the phone's
	 * own time zone. Calendar adds calendar days (not 24 h blocks), so a daylight-saving change in
	 * between still lands on 7 PM local.
	 */
	fun delayUntil(daysAhead: Int, hour: Int, nowMs: Long = System.currentTimeMillis()): Long {
		val target = Calendar.getInstance().apply {
			timeInMillis = nowMs
			add(Calendar.DAY_OF_YEAR, daysAhead)
			set(Calendar.HOUR_OF_DAY, hour)
			set(Calendar.MINUTE, 0)
			set(Calendar.SECOND, 0)
			set(Calendar.MILLISECOND, 0)
		}
		return (target.timeInMillis - nowMs).coerceAtLeast(0L)
	}

	fun ensureChannel(ctx: Context) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
		val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
		if (nm.getNotificationChannel(CHANNEL_ID) != null) return
		val channel = NotificationChannel(CHANNEL_ID, "Daily reminder", NotificationManager.IMPORTANCE_DEFAULT)
		channel.description = "One reminder a day for your daily bonus. Stops by itself after a week away."
		nm.createNotificationChannel(channel)
	}

	/** Posts one reminder; tapping it opens (or brings back) the game. Silently skips if notifications are off. */
	@SuppressLint("MissingPermission") // checked by enabled() just below
	fun show(ctx: Context, id: Int, title: String, body: String) {
		if (!enabled(ctx)) return
		ensureChannel(ctx)
		val builder = NotificationCompat.Builder(ctx, CHANNEL_ID)
			.setSmallIcon(R.drawable.namma_reminder_icon)
			.setColor(ACCENT)
			.setContentTitle(title)
			.setContentText(body)
			.setStyle(NotificationCompat.BigTextStyle().bigText(body))
			.setPriority(NotificationCompat.PRIORITY_DEFAULT)
			.setCategory(NotificationCompat.CATEGORY_REMINDER)
			.setAutoCancel(true)
		ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let { launch ->
			launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
			builder.setContentIntent(
				PendingIntent.getActivity(ctx, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
			)
		}
		try {
			NotificationManagerCompat.from(ctx).notify(TAG, id, builder.build())
		} catch (_: SecurityException) {
			// Permission revoked between the check and the post: nothing to show.
		}
	}
}
