package com.example.wake_up

import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.rodri.wakeup/pinning"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 1. ACORDAR ECRÃ
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        // 2. A MAGIA DO DEVICE OWNER (A LISTA VIP) 🌟
        // Isto diz ao Android: "Não perguntes nada, deixa esta app bloquear o ecrã!"
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminName = ComponentName(this, MyDeviceAdminReceiver::class.java)

            if (dpm.isDeviceOwnerApp(packageName)) {
                // Aqui definimos que a NOSSA app pode entrar em bloqueio sem confirmação
                dpm.setLockTaskPackages(adminName, arrayOf(packageName))
            }
        } catch (e: Exception) {
            // Ignorar se não for device owner ainda
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "pinApp") {
                try {
                    // Agora que estamos na "VIP List", este comando é silencioso!
                    startLockTask()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to pin: ${e.message}", null)
                }
            } else if (call.method == "unpinApp") {
                try {
                    stopLockTask()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to unpin: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}