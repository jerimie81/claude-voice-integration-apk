package com.redrum.claudevoice

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.redrum.claudevoice.databinding.ActivityMainBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.*
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity(), TextToSpeech.OnInitListener {

    private lateinit var binding: ActivityMainBinding
    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var isListening = false
    private var turnCount = 0

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(130, TimeUnit.SECONDS)
        .build()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        tts = TextToSpeech(this, this)

        val prefs = getSharedPreferences("claude_prefs", Context.MODE_PRIVATE)
        if (!prefs.contains("pc_ip")) {
            startActivity(Intent(this, SetupActivity::class.java))
        }

        checkPermissions()

        binding.btnSettings.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }

        binding.btnToggleOverlay.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                startActivity(intent)
            } else {
                val intent = Intent(this, OverlayService::class.java)
                if (isServiceRunning(OverlayService::class.java)) {
                    stopService(intent)
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                }
                updateOverlayButton()
            }
        }

        setupMicButton()
        updateOverlayButton()
    }

    private fun updateOverlayButton() {
        val running = isServiceRunning(OverlayService::class.java)
        binding.btnToggleOverlay.alpha = if (running) 1.0f else 0.5f
    }

    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }

    private fun checkPermissions() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
    }

    private fun setupMicButton() {
        binding.btnMic.setOnClickListener {
            if (isListening) stopListening() else startListening()
        }
        // Long-press resets the conversation history on the server.
        binding.btnMic.setOnLongClickListener {
            resetConversation()
            true
        }
    }

    private fun updateMicButton() {
        if (isListening) {
            binding.btnMic.setBackgroundResource(R.drawable.bg_mic_button_active)
            binding.btnMic.setImageResource(R.drawable.ic_mic_off)
        } else {
            binding.btnMic.setBackgroundResource(R.drawable.bg_mic_button)
            binding.btnMic.setImageResource(R.drawable.ic_mic)
        }
    }

    private fun startListening() {
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                binding.tvStatus.text = "Listening..."
            }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {
                binding.tvStatus.text = "Processing..."
                isListening = false
                updateMicButton()
            }
            override fun onError(error: Int) {
                isListening = false
                updateMicButton()
                binding.tvStatus.text = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH -> "No speech detected — tap mic to retry"
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech heard — tap mic to retry"
                    SpeechRecognizer.ERROR_AUDIO -> "Audio error"
                    SpeechRecognizer.ERROR_NETWORK -> "Network error"
                    else -> "STT Error: $error"
                }
            }
            override fun onResults(results: Bundle?) {
                isListening = false
                updateMicButton()
                val data = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val query = data?.get(0) ?: ""
                if (query.isNotEmpty()) {
                    binding.tvResponse.text = "You: $query\n\nClaude is thinking..."
                    binding.tvResponse.setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
                    sendToClaude(query)
                } else {
                    binding.tvStatus.text = "No speech detected — tap mic to retry"
                }
            }
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 5000L)
        }
        isListening = true
        updateMicButton()
        speechRecognizer?.startListening(intent)
    }

    private fun stopListening() {
        isListening = false
        updateMicButton()
        speechRecognizer?.stopListening()
    }

    private fun sendToClaude(query: String) {
        val prefs = getSharedPreferences("claude_prefs", Context.MODE_PRIVATE)
        val ip = prefs.getString("pc_ip", "10.7.0.1") ?: "10.7.0.1"
        val port = prefs.getString("pc_port", "5000") ?: "5000"
        val token = prefs.getString("pc_token", "") ?: ""

        if (ip.isEmpty()) {
            Toast.makeText(this, "Set PC IP in Settings first!", Toast.LENGTH_LONG).show()
            return
        }

        binding.tvStatus.text = "Waiting for Claude..."

        val timeoutSec = prefs.getString("pc_timeout", "300")?.toLongOrNull() ?: 300L
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(timeoutSec + 30, TimeUnit.SECONDS)
            .build()

        val url = "http://$ip:$port/claude/stream"
        val body = query.toRequestBody("text/plain".toMediaType())
        val requestBuilder = Request.Builder().url(url).post(body)
        if (token.isNotEmpty()) {
            requestBuilder.header("Authorization", "Bearer $token")
        }
        val request = requestBuilder.build()

        lifecycleScope.launch(Dispatchers.IO) {
            if (!isReachable(ip, port.toIntOrNull() ?: 5000, 1000)) {
                withContext(Dispatchers.Main) {
                    binding.tvResponse.text = "WireGuard tunnel not active — open the WireGuard app and toggle the tunnel on."
                    binding.tvResponse.setTextColor(ContextCompat.getColor(this@MainActivity, R.color.accent_red))
                    binding.tvStatus.text = "Tunnel down"
                }
                return@launch
            }
            try {
                val response = client.newCall(request).execute()

                if (response.code == 401) {
                    withContext(Dispatchers.Main) {
                        binding.tvResponse.text = "Auth failed — set the bearer token in Settings."
                        binding.tvResponse.setTextColor(ContextCompat.getColor(this@MainActivity, R.color.accent_red))
                        binding.tvStatus.text = "Unauthorized"
                    }
                    return@launch
                }

                val reader = response.body?.byteStream()?.bufferedReader()
                    ?: throw Exception("Empty response body")

                val fullResponse = StringBuilder()
                val sentenceBuffer = StringBuilder()

                for (line in reader.lineSequence()) {
                    if (!line.startsWith("data: ")) continue
                    val chunk = line.removePrefix("data: ")
                    if (chunk == "[DONE]") break
                    if (chunk.isEmpty()) continue

                    fullResponse.append(chunk).append(" ")
                    sentenceBuffer.append(chunk).append(" ")

                    // Speak each complete sentence as it arrives rather than waiting for the full response.
                    val text = sentenceBuffer.toString()
                    var lastBoundary = -1
                    for (sep in listOf(". ", "? ", "! ")) {
                        val idx = text.lastIndexOf(sep)
                        if (idx >= 0) {
                            val end = idx + sep.length
                            if (end > lastBoundary) lastBoundary = end
                        }
                    }
                    if (lastBoundary > 0) {
                        val sentence = text.substring(0, lastBoundary)
                        sentenceBuffer.delete(0, lastBoundary)
                        val display = fullResponse.toString().trim()
                        withContext(Dispatchers.Main) {
                            speak(sentence)
                            binding.tvResponse.text = "You: $query\n\nClaude: $display"
                        }
                    }
                }

                // Speak any sentence fragment that didn't end with a boundary marker.
                val remaining = sentenceBuffer.toString().trim()
                if (remaining.isNotEmpty()) {
                    withContext(Dispatchers.Main) { speak(remaining) }
                }

                turnCount++
                val finalDisplay = fullResponse.toString().trim()
                withContext(Dispatchers.Main) {
                    binding.tvResponse.text = "You: $query\n\nClaude: $finalDisplay"
                    binding.tvResponse.setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
                    binding.tvStatus.text = "Turn $turnCount | Ready"
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    binding.tvResponse.text = "Error: ${e.message}"
                    binding.tvResponse.setTextColor(ContextCompat.getColor(this@MainActivity, R.color.accent_red))
                    binding.tvStatus.text = "Connection failed"
                }
            }
        }
    }

    private fun resetConversation() {
        val prefs = getSharedPreferences("claude_prefs", Context.MODE_PRIVATE)
        val ip = prefs.getString("pc_ip", "10.7.0.1") ?: "10.7.0.1"
        val port = prefs.getString("pc_port", "5000") ?: "5000"
        val token = prefs.getString("pc_token", "") ?: ""

        val url = "http://$ip:$port/reset"
        val requestBuilder = Request.Builder().url(url).post("".toRequestBody())
        if (token.isNotEmpty()) {
            requestBuilder.header("Authorization", "Bearer $token")
        }
        val request = requestBuilder.build()

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                httpClient.newCall(request).execute()
            } catch (_: Exception) { }
            withContext(Dispatchers.Main) {
                turnCount = 0
                binding.tvResponse.text = ""
                binding.tvStatus.text = "Ready"
                Toast.makeText(this@MainActivity, "Conversation reset", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun isReachable(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            java.net.Socket().use { sock ->
                sock.connect(java.net.InetSocketAddress(host, port), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun sanitizeForTts(text: String): String =
        text.replace(Regex("[`*#_\\[\\]()]"), "")
            .replace(Regex("\\s{2,}"), " ")
            .trim()

    private fun speak(text: String) {
        tts?.speak(sanitizeForTts(text), TextToSpeech.QUEUE_ADD, null, "claude_response")
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.getDefault()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        speechRecognizer?.destroy()
        tts?.stop()
        tts?.shutdown()
    }
}
