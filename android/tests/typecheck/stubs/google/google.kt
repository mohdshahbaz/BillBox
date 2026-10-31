@file:Suppress("unused", "UNUSED_PARAMETER")
package com.google.android.gms.tasks
abstract class Task<T>
object Tasks { @JvmStatic fun <T> await(task: Task<T>): T = TODO() }
