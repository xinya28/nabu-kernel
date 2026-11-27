package org.bakasu.bakasu

import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.bakasu.bakasu.di.appModules
import org.bakasu.bakasu.domain.usecase.InitializeApplicationUseCase
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin

/**
 * Replaces the custom Application class of the stock manager.
 *
 * The manager is a single-process app except for the optional LKM "MagicaService"
 * helper, which the stock Application skipped too. A ContentProvider is created
 * before any Activity, so Koin and the application initialisation still happen
 * exactly once, before the UI needs them.
 */
class AppInitProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        val app = context?.applicationContext ?: return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val processName = Application.getProcessName()
            if (processName.endsWith("MagicaService")) return true
        }
        val koin = startKoin {
            androidLogger()
            androidContext(app)
            modules(appModules)
        }.koin
        runBlocking(Dispatchers.IO) {
            koin.get<InitializeApplicationUseCase>()()
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int = 0
}
