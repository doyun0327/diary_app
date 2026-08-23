package com.example.diary_app

import android.app.Application
import android.util.Log
import androidx.work.Configuration

/**
 * WorkManagerInitializer 자동 등록을 Manifest에서 제거했으므로,
 * Configuration.Provider로 on-demand 초기화를 제공합니다.
 * (없으면 AdMob/FCM이 WorkManager 사용 시 시작 직후 크래시)
 */
class DiaryApplication : Application(), Configuration.Provider {
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(Log.INFO)
            .build()
}
