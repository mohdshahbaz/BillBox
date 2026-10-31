@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.activity.result.contract
import android.net.Uri
abstract class ActivityResultContract<I, O>
class ActivityResultContracts {
    class OpenDocument : ActivityResultContract<Array<String>, Uri?>()
    class OpenMultipleDocuments : ActivityResultContract<Array<String>, List<Uri>>()
    class OpenDocumentTree : ActivityResultContract<Uri?, Uri?>()
    class CreateDocument(mimeType: String) : ActivityResultContract<String, Uri?>()
    class TakePicture : ActivityResultContract<Uri, Boolean>()
    class PickVisualMedia : ActivityResultContract<androidx.activity.result.PickVisualMediaRequest, Uri?>() {
        sealed interface VisualMediaType
        object ImageOnly : VisualMediaType
    }
}
