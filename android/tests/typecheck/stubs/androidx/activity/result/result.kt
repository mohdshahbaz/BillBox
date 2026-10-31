@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.activity.result
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
abstract class ActivityResultLauncher<I> { abstract fun launch(input: I); abstract fun unregister() }
fun interface ActivityResultCallback<O> { fun onActivityResult(result: O) }
abstract class ActivityResultRegistry { fun <I, O> register(key: String, contract: ActivityResultContract<I, O>, callback: ActivityResultCallback<O>): ActivityResultLauncher<I> = TODO() }
class PickVisualMediaRequest
fun PickVisualMediaRequest(mediaType: ActivityResultContracts.PickVisualMedia.VisualMediaType): PickVisualMediaRequest = TODO()
