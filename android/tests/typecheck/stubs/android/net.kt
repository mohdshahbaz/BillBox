package android.net
abstract class Uri : android.os.Parcelable { abstract val lastPathSegment: String?; companion object { fun parse(s: String): Uri = TODO(); fun fromFile(f: java.io.File): Uri = TODO() } }
