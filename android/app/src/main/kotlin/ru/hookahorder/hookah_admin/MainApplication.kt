package ru.hookahorder.hookah_admin

import android.app.Application
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MapKitFactory.setLocale("ru_RU")
        MapKitFactory.setApiKey(BuildConfig.YANDEX_MAPS_API_KEY)
    }
}
