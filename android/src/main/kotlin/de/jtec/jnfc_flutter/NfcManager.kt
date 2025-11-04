package de.jtec.jnfc_flutter

import android.app.Activity
import android.nfc.*
import android.nfc.tech.Ndef
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.nio.charset.Charset
import java.util.Locale

/**
 * Handles NFC ReaderMode, NDEF read/write, and reports via callbacks.
 */
class NfcManager(
    private val mainHandler: Handler = Handler(Looper.getMainLooper())
) : NfcAdapter.ReaderCallback {

    interface Callbacks {
        fun onCardRead(uid: String, content: String)
        fun onWriteResult(success: Boolean, error: String?)
        fun onError(message: String)
    }

    private var activity: Activity? = null
    private var adapter: NfcAdapter? = null
    private var callbacks: Callbacks? = null

    private var expectedUid: String? = null
    private var pendingWriteText: String? = null
    private var readingActive: Boolean = false
    private var writingActive: Boolean = false

    fun bind(activity: Activity, callbacks: Callbacks) {
        this.activity = activity
        this.adapter = NfcAdapter.getDefaultAdapter(activity)
        this.callbacks = callbacks
    }

    fun unbind() {
        disableReaderMode()
        this.activity = null
        this.adapter = null
        this.callbacks = null
    }

    fun startReading() {
        val act = activity ?: return
        val adp = adapter
        if (adp == null) {
            callbacks?.onError("NFC adapter not available")
            return
        }
        expectedUid = null
        pendingWriteText = null
        readingActive = true
        writingActive = false
        enableReaderMode(act)
    }

    fun stopReading() {
        readingActive = false
        disableReaderMode()
    }

    fun startWriting(uidRequirement: String?, text: String) {
        val act = activity ?: return
        val adp = adapter
        if (adp == null) {
            callbacks?.onWriteResult(false, "NFC adapter not available")
            return
        }
        expectedUid = uidRequirement?.uppercase(Locale.ROOT)
        pendingWriteText = text
        writingActive = true
        readingActive = false
        enableReaderMode(act)
    }

    override fun onTagDiscovered(tag: Tag?) {
        if (tag == null) return

        val uidHex = tagIdHex(tag.id)

        // If we require a specific UID for writing, enforce it
        if (writingActive) {
            expectedUid?.let { req ->
                if (uidHex.uppercase(Locale.ROOT) != req) {
                    // Wrong card → keep session alive; user can present another tag
                    //postAlert("Wrong tag. Expected $req, got $uidHex.")
                    return
                }
            }
        }

        // Read flow
        if (readingActive) {
            handleRead(tag, uidHex)
            return
        }

        // Write flow
        if (writingActive) {
            val text = pendingWriteText
            if (text.isNullOrEmpty()) {
                postWrite(false, "No data to write")
                return
            }
            handleWrite(tag, uidHex, text)
        }
    }

    // --- Internals ---

    private fun handleRead(tag: Tag, uidHex: String) {
        val ndef = Ndef.get(tag)
        if (ndef == null) {
            postCard(uidHex, "<no NDEF support>")
            return
        }
        try {
            ndef.connect()
            val msg = ndef.ndefMessage
            val text = firstTextFrom(msg) ?: "<no text>"
            postCard(uidHex, text)
        } catch (t: Throwable) {
            postError("Read failed: ${t.message}")
        } finally {
            try { ndef.close() } catch (_: Throwable) {}
        }
    }

    private fun handleWrite(tag: Tag, uidHex: String, text: String) {
        val ndef = Ndef.get(tag)
        if (ndef == null) {
            postWrite(false, "Tag does not support NDEF")
            return
        }
        try {
            ndef.connect()
            if (!ndef.isWritable) {
                postWrite(false, "Tag is read-only")
                return
            }

            val msg = makeTextMessage(text, Locale.getDefault().language.ifEmpty { "en" })
            val needed = msg.toByteArray().size
            val cap = ndef.maxSize
            if (needed > cap) {
                postWrite(false, "Not enough space (need $needed, have $cap)")
                return
            }

            ndef.writeNdefMessage(msg)

            // optional: verify by read-back
            val readBack = try {
                ndef.ndefMessage
            } catch (_: Throwable) {
                null
            }
            val content = firstTextFrom(readBack) ?: "<no text>"

            // surface content as a convenience (mirrors iOS side)
            postCard(uidHex, content)
            postWrite(true, null)
        } catch (t: Throwable) {
            postWrite(false, "Write failed: ${t.message}")
        } finally {
            try { ndef.close() } catch (_: Throwable) {}
            // Keep reader mode on so user can retry another card if needed
        }
    }

    private fun enableReaderMode(activity: Activity) {
        val flags = (NfcAdapter.FLAG_READER_NFC_A
                or NfcAdapter.FLAG_READER_NFC_B
                or NfcAdapter.FLAG_READER_NFC_F
                or NfcAdapter.FLAG_READER_NFC_V
                // or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
        )
        val extras = Bundle().apply {
            // Optional tuning:
            // putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 100)
        }
        adapter?.enableReaderMode(activity, this, flags, extras)
    }

    private fun disableReaderMode() {
        activity?.let { act ->
            try { adapter?.disableReaderMode(act) } catch (_: Throwable) {}
        }
    }

    private fun tagIdHex(id: ByteArray?): String {
        if (id == null) return "<unavailable>"
        return id.joinToString(":") { b -> "%02X".format(b) }
    }

    private fun postCard(uid: String, content: String) {
        mainHandler.post { callbacks?.onCardRead(uid, content) }
    }

    private fun postWrite(success: Boolean, error: String?) {
        mainHandler.post {
            callbacks?.onWriteResult(success, error)
            // Writing session remains enabled; caller can call stopReading() to end if desired.
            // If you prefer auto-stop on success, you could call disableReaderMode() here.
        }
    }

    private fun postError(msg: String) {
        mainHandler.post { callbacks?.onError(msg) }
    }

    // --- NDEF helpers ---

    private fun makeTextMessage(text: String, language: String): NdefMessage {
        val langBytes = language.toByteArray(Charset.forName("US-ASCII"))
        val textBytes = text.toByteArray(Charset.forName("UTF-8"))
        val payload = ByteArray(1 + langBytes.size + textBytes.size)
        payload[0] = (langBytes.size and 0x3F).toByte() // UTF-8 + lang length
        System.arraycopy(langBytes, 0, payload, 1, langBytes.size)
        System.arraycopy(textBytes, 0, payload, 1 + langBytes.size, textBytes.size)

        val record = NdefRecord(
            NdefRecord.TNF_WELL_KNOWN,
            NdefRecord.RTD_TEXT,
            ByteArray(0),
            payload
        )
        return NdefMessage(arrayOf(record))
    }

    private fun firstTextFrom(message: NdefMessage?): String? {
        if (message == null) return null
        for (rec in message.records) {
            if (rec.tnf == NdefRecord.TNF_WELL_KNOWN && rec.type.contentEquals(NdefRecord.RTD_TEXT)) {
                val payload = rec.payload
                if (payload.isEmpty()) return ""
                val status = payload[0].toInt()
                val langLen = status and 0x3F
                val textBytes = payload.copyOfRange(1 + langLen, payload.size)
                return try {
                    String(textBytes, Charset.forName("UTF-8"))
                } catch (_: Throwable) {
                    null
                }
            }
        }
        return null
    }
}