# Claude Voice integration — Voice APK

A self-contained Android Voice APK that integrates with a Claude-powered PC server.  
Features Push-to-Talk (PTT), on-device STT, direct HTTP communication, and automatic TTS response.

---

## Features

- **Push-to-Talk (PTT)**: Large mic button for recording.
- **On-device STT**: Uses Android's native `SpeechRecognizer`.
- **Direct PC Relay**: Sends queries directly to the PC Flask server (no Termux dependency for voice).
- **Auto TTS**: Automatically speaks Claude's response aloud.
- **Visual Response**: Shows full text response in a scrollable view.
- **Floating Overlay**: Optional draggable mic bubble to trigger voice from any app.
- **Configurable**: Easy setup of PC IP and Port via in-app settings.

---

## Architecture

```
[Android App]  ──HTTP POST (query)──▶  [PC Flask Server]
      ▲                                       │
      │                                       ▼
[Text-to-Speech] ◀──HTTP Response (text)── [Claude CLI]
```

---

## Installation

### 1. PC Server

Install Flask:

```bash
pip install flask
```

Run the server:

```bash
python3 pc_server/claude_webhook_server.py
```

Ensure your PC is on the same LAN as your phone and note its LAN IP.

---

### 2. Android App

Build and install the APK:

```bash
cd android_app
# If gradlew is available:
./gradlew assembleDebug
# Otherwise, use a system gradle:
gradle assembleDebug

adb install app/build/outputs/apk/debug/app-debug.apk
```

---

## Configuration

1. Launch the **Claude Voice** app.
2. Grant **Microphone** and **Notification** permissions.
3. Tap the **Settings (cog)** icon in the top right.
4. Enter your **PC LAN IP** and **Port** (default 5000).
5. Tap **Save**.
6. (Optional) Tap **Show Overlay** to enable the floating mic bubble. You will need to grant "Display over other apps" permission.

---

## Usage

- **Main App**: Press and hold the **Mic button**, speak your query, and release. Claude's response will be displayed and spoken aloud.
- **Overlay**: Tap the floating blue bubble to jump into the app and start talking. Drag the bubble to reposition it.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Set PC IP in Settings first!` | Go to Settings and enter your PC's LAN IP address. |
| `STT Error` | Ensure the app has Microphone permissions and your device supports Google Speech Services. |
| `Failed to connect` | Check if the PC server is running and accessible on the LAN. Ensure the Port is correct. |
| No sound | Check your media volume and ensure Text-to-Speech is configured in Android system settings. |
