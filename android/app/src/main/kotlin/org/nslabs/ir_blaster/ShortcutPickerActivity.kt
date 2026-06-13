package org.nslabs.ir_blaster

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Hosts the "pick a button or macro" UI shown when an external key-remapper tool
 * (or any launcher) creates a shortcut via [Intent.ACTION_CREATE_SHORTCUT].
 *
 * It runs in its own task (see manifest taskAffinity/excludeFromRecents) so it never
 * interferes with a running instance of the main app. The Flutter side renders a minimal
 * picker app (selected via the "shortcut_picker" initial route) and calls back through
 * [CHANNEL] with the resolved IR payload, which we persist and return as a classic
 * launcher shortcut pointing at [IrShortcutFireActivity].
 */
class ShortcutPickerActivity : FlutterActivity() {

    override fun getInitialRoute(): String = INITIAL_ROUTE

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "submit" -> handleSubmit(call.arguments as? Map<*, *>, result)
                    "cancel" -> {
                        setResult(RESULT_CANCELED)
                        result.success(true)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSubmit(args: Map<*, *>?, result: MethodChannel.Result) {
        val payload = IrShortcutPayload.fromMap(args)
        if (payload == null) {
            result.error("BAD_PAYLOAD", "Shortcut payload is missing IR data.", null)
            return
        }

        val token = UUID.randomUUID().toString()
        IrShortcutStore.save(applicationContext, token, payload)

        val fireIntent = Intent(applicationContext, IrShortcutFireActivity::class.java).apply {
            action = IrShortcutFireActivity.ACTION_FIRE
            putExtra(IrShortcutFireActivity.EXTRA_TOKEN, token)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val resultIntent = Intent().apply {
            putExtra(Intent.EXTRA_SHORTCUT_INTENT, fireIntent)
            putExtra(Intent.EXTRA_SHORTCUT_NAME, payload.title)
            putExtra(
                Intent.EXTRA_SHORTCUT_ICON_RESOURCE,
                Intent.ShortcutIconResource.fromContext(
                    this@ShortcutPickerActivity, R.mipmap.ic_launcher),
            )
        }

        setResult(RESULT_OK, resultIntent)
        result.success(true)
        finish()
    }

    companion object {
        private const val CHANNEL = "org.nslabs/shortcut_picker"
        const val INITIAL_ROUTE = "shortcut_picker"
    }
}
