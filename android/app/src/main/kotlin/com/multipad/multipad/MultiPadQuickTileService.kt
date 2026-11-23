package com.multipad.multipad

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class MultiPadQuickTileService : TileService() {

    override fun onTileAdded() {
        super.onTileAdded()
        refreshTileState()
    }

    override fun onStartListening() {
        super.onStartListening()
        refreshTileState()
    }

    private fun refreshTileState() {
        val tile = qsTile ?: return
        tile.label = "MultiPad"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (MultiPadAccessibilityService.isRunning) "Hızlı Doldur" else "Hızlı Arama"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = "Hızlı Doldurma ve Kasa Arama"
        }
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_tile)
        tile.state = if (MultiPadAccessibilityService.isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()

        // 1. If Accessibility Service is running, directly trigger on-screen autofill
        if (MultiPadAccessibilityService.isRunning) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Collapse quick settings shade
                try {
                    val collapseIntent = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
                    sendBroadcast(collapseIntent)
                } catch (_) {}
            }
            MultiPadAccessibilityService.instance?.performQuickFill()
            return
        }

        // 2. Fallback: Launch Quick Search activity
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_MULTIPAD_ACTION, MainActivity.ACTION_QUICK_SEARCH)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
