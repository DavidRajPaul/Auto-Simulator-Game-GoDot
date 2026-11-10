package com.davidrajpaul.nammaauto.reminder

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.TimeUnit

/**
 * Local daily reminders for Namma Auto. No server, no Firebase: the game schedules a week of
 * one-shot reminders whenever it goes to the background and cancels them when it comes back
 * (autoloads/DailyReminder.gd), so a player who plays every day never sees one.
 *
 * GDScript: Engine.get_singleton("NammaReminder")
 *   scheduleAt(id, days_ahead, hour, title, body)  - hour:00 in the phone's own time zone
 *   schedule(id, delay_seconds, title, body)       - from now (debug test reminder)
 *   cancelAll(), notificationsEnabled(),
 *   requestPermission() -> signal permission_result(granted: bool)
 */
private const val PERMISSION = "android.permission.POST_NOTIFICATIONS"
private const val REQUEST_CODE = 7419
private const val WORK_TAG = Reminders.TAG

class NammaReminderPlugin(godot: Godot) : GodotPlugin(godot) {
	override fun getPluginName(): String = "NammaReminder"

	override fun getPluginSignals(): Set<SignalInfo> =
		setOf(SignalInfo("permission_result", Boolean::class.javaObjectType))

	@UsedByGodot
	fun notificationsEnabled(): Boolean {
		val ctx = context ?: return false
		return Reminders.enabled(ctx)
	}

	/** At [hour]:00 local time, [daysAhead] calendar days from today. Replaces a pending reminder with the same id. */
	@UsedByGodot
	fun scheduleAt(id: Int, daysAhead: Int, hour: Int, title: String, body: String) {
		enqueue(id, Reminders.delayUntil(daysAhead, hour), title, body)
	}

	/** [delaySeconds] from now. Replaces a pending reminder with the same id. */
	@UsedByGodot
	fun schedule(id: Int, delaySeconds: Int, title: String, body: String) {
		enqueue(id, TimeUnit.SECONDS.toMillis(delaySeconds.coerceAtLeast(0).toLong()), title, body)
	}

	@UsedByGodot
	fun cancelAll() {
		val ctx = context ?: return
		WorkManager.getInstance(ctx).cancelAllWorkByTag(WORK_TAG)
	}

	/**
	 * Android 13+: shows the system "Allow notifications?" dialog. If Android will not show it any
	 * more (denied twice) or notifications were switched off in system settings, opens the app's
	 * notification settings instead. Emits permission_result when the dialog answers.
	 */
	@UsedByGodot
	fun requestPermission() {
		runOnHostThread { askOrOpenSettings() }
	}

	private fun enqueue(id: Int, delayMs: Long, title: String, body: String) {
		val ctx = context ?: return
		Reminders.ensureChannel(ctx)
		val data = Data.Builder()
			.putInt(Reminders.KEY_ID, id)
			.putString(Reminders.KEY_TITLE, title)
			.putString(Reminders.KEY_BODY, body)
			.build()
		val request = OneTimeWorkRequest.Builder(ReminderWorker::class.java)
			.setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
			.setInputData(data)
			.addTag(WORK_TAG)
			.build()
		WorkManager.getInstance(ctx).enqueueUniqueWork("${WORK_TAG}_$id", ExistingWorkPolicy.REPLACE, request)
	}

	private fun askOrOpenSettings() {
		val activity = activity ?: return
		if (Reminders.enabled(activity)) {
			emitSignal("permission_result", true)
			return
		}
		if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED) {
			val prefs = activity.getSharedPreferences(Reminders.PREFS, Context.MODE_PRIVATE)
			val askedBefore = prefs.getBoolean("asked", false)
			if (!askedBefore || activity.shouldShowRequestPermissionRationale(PERMISSION)) {
				prefs.edit().putBoolean("asked", true).apply()
				activity.requestPermissions(arrayOf(PERMISSION), REQUEST_CODE)
				return
			}
		}
		openNotificationSettings(activity)
	}

	private fun openNotificationSettings(activity: Activity) {
		val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
		} else {
			Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
		}
		try {
			activity.startActivity(intent)
		} catch (e: ActivityNotFoundException) {
			Log.w(Reminders.TAG, "No settings screen for notifications", e)
		}
	}

	override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<String>?, grantResults: IntArray?) {
		if (requestCode != REQUEST_CODE) return
		emitSignal("permission_result", notificationsEnabled())
	}
}
