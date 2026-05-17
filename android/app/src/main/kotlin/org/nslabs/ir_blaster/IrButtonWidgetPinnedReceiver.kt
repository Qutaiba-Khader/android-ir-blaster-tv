package org.nslabs.ir_blaster

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class IrButtonWidgetPinnedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra(EXTRA_PENDING_TOKEN).orEmpty()
        val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val mapping = IrButtonWidgetStore.popPending(context, token)
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID && mapping != null) {
            IrButtonWidgetStore.saveMapping(context, appWidgetId, mapping)
            IrButtonWidgetProvider.updateWidget(context, AppWidgetManager.getInstance(context), appWidgetId)
        }
    }

    companion object {
        const val EXTRA_PENDING_TOKEN = "pending_widget_token"
    }
}
