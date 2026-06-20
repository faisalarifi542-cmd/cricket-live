package com.cric.pro.ads

import android.os.Handler
import io.flutter.plugin.common.MethodChannel

/**
 * Wraps a [MethodChannel.Result] so it is always replied to exactly once and on
 * the platform (main) thread. Ad SDK callbacks can fire on background threads
 * or fire twice (e.g. fail + dismiss); this prevents crashes from a double or
 * off-thread reply.
 */
class SafeResult(
    private val main: Handler,
    private val result: MethodChannel.Result,
) {
    @Volatile
    private var replied = false

    fun success(value: Any?) {
        if (replied) return
        replied = true
        main.post { result.success(value) }
    }

    fun error(code: String, message: String?) {
        if (replied) return
        replied = true
        main.post { result.error(code, message, null) }
    }
}

