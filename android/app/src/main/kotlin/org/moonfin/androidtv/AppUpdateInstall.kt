package org.moonfin.androidtv

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

// Shares the downloaded update APK (cache/sunfin_update/) with the system
// package installer. Its own class, so no plugin's FileProvider entry in the
// merged manifest can collide with it.
class SunfinUpdateFileProvider : FileProvider()

// Sunfin: hands a downloaded update APK to the system package installer.
// Android asks the user to confirm, asks for the "install unknown apps"
// permission first if Sunfin doesn't have it yet, and refuses an APK signed
// with another key than the installed app.
object AppUpdateInstall {
    fun open(context: Context, apk: File): Boolean {
        if (!apk.isFile) return false
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.updates",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
