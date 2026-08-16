package com.wisp.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE verhindert Screenshots und Screen-Recording.
        // Schützt die Privatsphäre: Keine Fotos/Chats anderer Nutzer
        // können via Screenshot unkontrolliert weitergegeben werden.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}
