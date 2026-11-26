package com.davidrajpaul.nammaauto.reminder

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
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
	const val KEY_LOOK = "look"
	const val KEY_CHIP = "chip"
	const val KEY_ACTION = "action"
	private const val KEY_ACTIVE = "reminders_active"

	fun setActive(ctx: Context, active: Boolean) {
		ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ACTIVE, active).commit()
	}

	fun isActive(ctx: Context): Boolean =
		ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ACTIVE, false)

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

	/**
	 * A card look: gradient, right-hand art and round icon (tools/art/make_notification_art.py).
	 * DailyReminder.gd picks one per message: bonus, streak, jackpot, street.
	 */
	private class Look(val bg: Int, val art: Int, val icon: Int)

	private fun look(name: String?): Look = when (name) {
		"bonus" -> Look(R.drawable.namma_notif_bg_bonus, R.drawable.namma_notif_art_bonus, R.drawable.namma_notif_icon_bonus)
		"streak" -> Look(R.drawable.namma_notif_bg_streak, R.drawable.namma_notif_art_streak, R.drawable.namma_notif_icon_streak)
		"jackpot" -> Look(R.drawable.namma_notif_bg_jackpot, R.drawable.namma_notif_art_jackpot, R.drawable.namma_notif_icon_jackpot)
		else -> Look(R.drawable.namma_notif_bg_street, R.drawable.namma_notif_art_street, R.drawable.namma_notif_icon_street)
	}

	/** Fills one of the two card layouts. [chip] (e.g. "₹50", "DAY 4") hides when empty; so does the CTA pill. */
	private fun card(ctx: Context, layout: Int, l: Look, title: String, body: String, chip: String, action: String): RemoteViews {
		val v = RemoteViews(ctx.packageName, layout)
		v.setInt(R.id.namma_notif_root, "setBackgroundResource", l.bg)
		v.setTextViewText(R.id.namma_notif_title, title)
		v.setTextViewText(R.id.namma_notif_body, body)
		v.setTextViewText(R.id.namma_notif_chip, chip)
		v.setViewVisibility(R.id.namma_notif_chip, if (chip.isBlank()) View.GONE else View.VISIBLE)
		if (layout == R.layout.namma_notif_expanded) {
			v.setImageViewResource(R.id.namma_notif_art, l.art)
			v.setTextViewText(R.id.namma_notif_cta, "$action  \u203A")
			v.setViewVisibility(R.id.namma_notif_cta, if (action.isBlank()) View.GONE else View.VISIBLE)
		} else {
			v.setImageViewResource(R.id.namma_notif_icon, l.icon)
		}
		return v
	}

	/**
	 * Posts one reminder as a game-style card (DecoratedCustomViewStyle: the system keeps its header,
	 * small icon and action row; the content is our gradient + art). Title and text are still set
	 * for the lock screen, accessibility and anything that ignores custom views.
	 * Tapping the card or its action opens (or brings back) the game. Silently skips if notifications are off.
	 */
	@SuppressLint("MissingPermission") // checked by enabled() just below
	fun show(ctx: Context, id: Int, title: String, body: String, lookName: String? = null, chip: String = "", action: String = "") {
		if (!enabled(ctx) || !isActive(ctx)) return
		ensureChannel(ctx)
		val l = look(lookName)
		val builder = NotificationCompat.Builder(ctx, CHANNEL_ID)
			.setSmallIcon(R.drawable.namma_reminder_icon)
			.setColor(ACCENT)
			.setContentTitle(title)
			.setContentText(body)
			.setStyle(NotificationCompat.DecoratedCustomViewStyle())
			.setCustomContentView(card(ctx, R.layout.namma_notif_collapsed, l, title, body, chip, action))
			.setCustomHeadsUpContentView(card(ctx, R.layout.namma_notif_collapsed, l, title, body, chip, action))
			.setCustomBigContentView(card(ctx, R.layout.namma_notif_expanded, l, title, body, chip, action))
			.setPriority(NotificationCompat.PRIORITY_DEFAULT)
			.setCategory(NotificationCompat.CATEGORY_REMINDER)
			.setAutoCancel(true)
		ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let { launch ->
			launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
			val open = PendingIntent.getActivity(ctx, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
			builder.setContentIntent(open)
			if (action.isNotBlank()) builder.addAction(0, action, open)
		}
		try {
			NotificationManagerCompat.from(ctx).notify(TAG, id, builder.build())
		} catch (_: SecurityException) {
			// Permission revoked between the check and the post: nothing to show.
		}
	}
}
