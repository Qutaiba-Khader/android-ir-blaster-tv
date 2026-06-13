package org.nslabs.ir_blaster

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.ConsumerIrManager
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast

/**
 * Invisible, no-UI activity that fires a stored [IrShortcutPayload] when a remapped
 * physical key (via tvQuickActions / Button Mapper / Key Mapper / any launcher shortcut)
 * triggers the shortcut intent. It transmits IR natively on a background thread and
 * finishes immediately, so nothing is drawn on screen.
 *
 * Transmit paths are tried natively (no Flutter, no visible UI): the built-in IR emitter
 * first, then an attached & permitted USB IR dongle. Only if no native transmitter can be
 * acquired (e.g. USB permission has never been granted) does it fall back to opening the
 * app so the user can complete setup.
 */
class IrShortcutFireActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val token = intent?.getStringExtra(EXTRA_TOKEN)?.trim().orEmpty()
        val payload = if (token.isNotEmpty()) IrShortcutStore.load(applicationContext, token) else null
        if (payload == null) {
            finish()
            return
        }

        val appContext = applicationContext
        Thread {
            val internalTx = InternalIrTransmitter(appContext.getSystemService(ConsumerIrManager::class.java))
            val usbTx = acquireUsbTransmitter(appContext)
            try {
                var sentAny = false
                for ((index, step) in payload.steps.withIndex()) {
                    // Built-in emitter first, then USB dongle — both fully native.
                    val ok = internalTx.transmitRaw(step.frequencyHz, step.pattern) ||
                        (usbTx?.transmitRaw(step.frequencyHz, step.pattern) == true)
                    if (!ok) {
                        if (!sentAny && payload.fallbackButtonId.isNotEmpty()) {
                            // No usable native transmitter (likely USB permission not yet
                            // granted). Open the app so the user can grant it / pick an emitter.
                            fallbackToFlutter(payload)
                        } else {
                            showToast("IR transmitter unavailable.")
                        }
                        break
                    }
                    sentAny = true
                    if (step.delayAfterMs > 0 && index < payload.steps.size - 1) {
                        try {
                            Thread.sleep(step.delayAfterMs.toLong())
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                }
            } finally {
                try {
                    usbTx?.close()
                } catch (_: Throwable) {
                }
            }
        }.start()

        // Never show UI: kick off the transmit thread and leave immediately.
        finish()
    }

    /**
     * Opens an attached, already-permitted USB IR dongle for a one-shot transmit. Returns
     * null if there is no supported device or permission was never granted (we can't show a
     * permission dialog silently). Reuses the same discovery used by the main app.
     */
    private fun acquireUsbTransmitter(context: Context): UsbIrTransmitter? {
        return try {
            val usb = context.getSystemService(Context.USB_SERVICE) as? UsbManager ?: return null
            val disc = UsbDiscoveryManager(context, usb)
            val device = disc.scanSupported().firstOrNull() ?: return null
            if (!usb.hasPermission(device)) return null
            disc.openTransmitter(device)
        } catch (_: Throwable) {
            null
        }
    }

    private fun fallbackToFlutter(payload: IrShortcutPayload) {
        try {
            applicationContext.startActivity(
                Intent(applicationContext, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(DeviceControlsService.EXTRA_CONTROL_BUTTON_ID, payload.fallbackButtonId)
                },
            )
        } catch (_: Throwable) {
            showToast("IR transmitter unavailable.")
        }
    }

    private fun showToast(message: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        const val ACTION_FIRE = "org.nslabs.irblaster.shortcut.FIRE"
        const val EXTRA_TOKEN = "ir_shortcut_token"
    }
}
