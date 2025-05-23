package com.linusu.flutter_web_auth

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.net.Uri

class CallbackActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    val callbackUri: Uri? = intent?.data
    if (callbackUri != null) {
      val launchIntent = Intent(Intent.ACTION_VIEW, callbackUri)
      launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      applicationContext.startActivity(launchIntent)
    }

    finish()
  }
}
