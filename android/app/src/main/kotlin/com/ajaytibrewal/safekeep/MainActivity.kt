package com.ajaytibrewal.safekeep

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE, set once for the whole activity, does three things
        // this app needs:
        //   - blocks screenshots and screen recording,
        //   - blanks the app-switcher thumbnail, so document contents are
        //     not left visible in the recents list,
        //   - prevents the window appearing on non-secure external
        //     displays or being captured by most screen-sharing apps.
        //
        // Applied unconditionally rather than only on screens showing
        // documents. Toggling it per screen leaves a window during the
        // transition where the flag is not yet set, and the recents
        // thumbnail is captured exactly when the app is leaving the
        // foreground — precisely the moment a per-screen approach is
        // least likely to have got there first.
        //
        // The cost is that users cannot screenshot anything, including
        // onboarding. For a document vault that is the right trade.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
