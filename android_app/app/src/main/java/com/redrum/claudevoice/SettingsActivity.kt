package com.redrum.claudevoice

import android.content.Context
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.redrum.claudevoice.databinding.ActivitySettingsBinding

class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val prefs = getSharedPreferences("claude_prefs", Context.MODE_PRIVATE)
        binding.etIp.setText(prefs.getString("pc_ip", "10.7.0.1"))
        binding.etPort.setText(prefs.getString("pc_port", "5000"))
        binding.etToken.setText(prefs.getString("pc_token", ""))
        binding.etTimeout.setText(prefs.getString("pc_timeout", "300"))

        binding.btnSave.setOnClickListener {
            val ip = binding.etIp.text.toString().trim()
            val port = binding.etPort.text.toString().trim()
            val token = binding.etToken.text.toString().trim()
            val timeout = binding.etTimeout.text.toString().trim()

            if (ip.isEmpty() || port.isEmpty() || timeout.isEmpty()) {
                Toast.makeText(this, "Please enter IP, Port, and Timeout", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            prefs.edit()
                .putString("pc_ip", ip)
                .putString("pc_port", port)
                .putString("pc_token", token)
                .putString("pc_timeout", timeout)
                .apply()

            Toast.makeText(this, "Settings saved", Toast.LENGTH_SHORT).show()
            finish()
        }
    }
}
