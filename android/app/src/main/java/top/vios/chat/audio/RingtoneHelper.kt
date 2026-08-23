package top.vios.chat.audio

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.provider.Settings
import android.util.Log

/**
 * 铃声管理器
 * - 通知铃声：收到消息时播放
 * - 语音来电铃声 / 视频来电铃声：来电时循环播放，可自定义
 * 铃声选择通过系统 RingtonePicker，URI 持久化在 SharedPreferences
 */
object RingtoneHelper {

    private const val PREFS = "everett_ringtones"
    const val KEY_NOTIFY = "ring_notify"
    const val KEY_VOICE = "ring_voice_call"
    const val KEY_VIDEO = "ring_video_call"

    private var player: MediaPlayer? = null
    private var currentStream = AudioManager.STREAM_RING

    /* ============ 配置存取 ============ */

    fun getNotifyUri(context: Context): Uri {
        val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_NOTIFY, null)
        if (saved != null) return Uri.parse(saved)
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    }

    fun getVoiceCallUri(context: Context): Uri {
        val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_VOICE, null)
        if (saved != null) return Uri.parse(saved)
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    }

    fun getVideoCallUri(context: Context): Uri {
        val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_VIDEO, null)
        if (saved != null) return Uri.parse(saved)
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    }

    fun saveUri(context: Context, key: String, uri: Uri) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(key, uri.toString()).apply()
    }

    /** 构建系统铃声选择器 Intent */
    fun buildRingtonePicker(context: Context, type: Int, existingUri: Uri?): Intent {
        return Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, type)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, existingUri)
        }
    }

    /* ============ 播放 ============ */

    /** 播放通知提示音 */
    fun playNotification(context: Context) {
        try {
            val uri = getNotifyUri(context)
            if (uri.toString() == Settings.System.DEFAULT_RINGTONE_URI.toString() && false) return
            val p = MediaPlayer()
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            p.setDataSource(context, uri)
            p.setOnCompletionListener { it.release() }
            p.prepare()
            p.start()
        } catch (e: Exception) {
            Log.w("RingtoneHelper", "playNotification: ${e.message}")
        }
    }

    /**
     * 播放来电铃声（循环，直到 stopRingtone）
     * @param isVideo true=视频来电（用视频铃声），false=语音来电
     */
    fun playIncomingCall(context: Context, isVideo: Boolean) {
        stopRingtone()
        try {
            val uri = if (isVideo) getVideoCallUri(context) else getVoiceCallUri(context)
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            // 来电铃声响铃流 + 震动
            am.ringerMode?.let { }
            currentStream = AudioManager.STREAM_RING
            val p = MediaPlayer()
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            p.setDataSource(context, uri)
            p.isLooping = true
            p.setOnPreparedListener { it.start() }
            p.prepareAsync()
            player = p
        } catch (e: Exception) {
            Log.w("RingtoneHelper", "playIncomingCall: ${e.message}")
        }
    }

    /** 停止来电铃声 */
    fun stopRingtone() {
        try {
            player?.stop()
        } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
    }

    fun isRinging() = player?.isPlaying == true
}