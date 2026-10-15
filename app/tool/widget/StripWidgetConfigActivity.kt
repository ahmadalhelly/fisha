package com.mttlhub.mttl_hub

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle

/** Shown when a strip widget is placed: pick which strip it shows. */
class StripWidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        val id = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val j = FishaWidgets.data(this)
        val arr = j.optJSONArray("strips")
        if (arr == null || arr.length() == 0) {
            done(id, "")
            return
        }
        val names = Array<CharSequence>(arr.length()) { arr.getJSONObject(it).optString("name") }
        val title = if (j.optBoolean("ar", true)) "اختار المشترك" else "Choose a strip"
        AlertDialog.Builder(this)
            .setTitle(title)
            .setItems(names) { _, i -> done(id, arr.getJSONObject(i).optString("mac")) }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun done(id: Int, mac: String) {
        getSharedPreferences(FishaWidgets.PREFS, Context.MODE_PRIVATE).edit().putString("wstrip_" + id, mac).apply()
        FishaWidgets.updateAll(this)
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        finish()
    }
}
