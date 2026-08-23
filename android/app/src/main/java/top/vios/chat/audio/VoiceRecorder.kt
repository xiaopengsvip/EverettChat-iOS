package top.vios.chat.audio

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * 语音录制与播放封装
 * 录音: AAC/M4A (MediaRecorder) → 文件/ByteArray
 * 播放: MediaPlayer
 */
class VoiceRecorder(private val context: Context) {

    companion object {
        private const val TAG = "VoiceRecorder"
        const val MAX_DURATION_MS = 60_000  // 最长 60 秒
    }

    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null
    private var recordingStart = 0L

    /** 开始录音，返回输出文件（用于计时/取消） */
    fun start(): File? {
        return try {
            val dir = File(context.cacheDir, "voice").apply { mkdirs() }
            val file = File(dir, "rec_${System.currentTimeMillis()}.m4a")
            val r = if (android.os.Build.VERSION.SDK_INT >= 31) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioSamplingRate(44100)
            r.setAudioEncodingBitRate(128_000)
            r.setOutputFile(file.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            outputFile = file
            recordingStart = System.currentTimeMillis()
            file
        } catch (e: Exception) {
            Log.e(TAG, "start failed: ${e.message}")
            null
        }
    }

    /** 停止录音，返回录音数据（null=失败/太短） */
    fun stop(): ByteArray? {
        return try {
            val r = recorder ?: return null
            val elapsed = System.currentTimeMillis() - recordingStart
            if (elapsed < 500) { // 太短视为取消
                r.stop()
                r.release()
                recorder = null
                outputFile?.delete()
                return null
            }
            r.stop()
            r.release()
            recorder = null
            val f = outputFile ?: return null
            val data = f.readBytes()
            f.delete()
            if (data.size < 1024) null else data
        } catch (e: Exception) {
            Log.e(TAG, "stop failed: ${e.message}")
            try { recorder?.release() } catch (_: Exception) {}
            recorder = null
            null
        }
    }

    /** 取消录音（不发送） */
    fun cancel() {
        try {
            recorder?.stop()
        } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
        outputFile?.delete()
        outputFile = null
    }

    /** 当前录音时长（毫秒） */
    fun currentDurationMs(): Long = System.currentTimeMillis() - recordingStart

    fun isRecording() = recorder != null

    /* ============ 播放 ============ */

    private var player: MediaPlayer? = null
    private var playingFile: File? = null

    /** 播放 ByteArray 语音（保存到缓存后播放） */
    fun play(data: ByteArray, onComplete: (() -> Unit)? = null) {
        stopPlayback()
        try {
            val dir = File(context.cacheDir, "voice_play").apply { mkdirs() }
            val f = File(dir, "play_${System.currentTimeMillis()}.m4a")
            FileOutputStream(f).use { it.write(data) }
            playingFile = f
            val p = MediaPlayer()
            p.setDataSource(f.absolutePath)
            p.setOnCompletionListener {
                stopPlayback()
                onComplete?.invoke()
            }
            p.setOnErrorListener { _, _, _ ->
                stopPlayback()
                onComplete?.invoke()
                true
            }
            p.prepare()
            p.start()
            player = p
        } catch (e: Exception) {
            Log.e(TAG, "play failed: ${e.message}")
            onComplete?.invoke()
        }
    }

    fun isPlaying() = player?.isPlaying == true

    fun stopPlayback() {
        try {
            player?.stop()
        } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
        playingFile?.delete()
        playingFile = null
    }
}