# MeetingNotes

A light menu-bar Mac app that records a Zoom meeting **locally** and writes summary + long notes.
It does not join the call as a bot, so Zoom shows nothing to other participants.

- **Others' audio**: captured from the Zoom app only (ScreenCaptureKit). **Your voice**: microphone.
- **Who said what**: in Zoom's Gallery view the active speaker gets a green border. About once a second
  the app finds that border in the Zoom window and reads the name label with on-device OCR (Vision),
  so the transcript says `Albert Dow:` instead of `Others:`. Frames are never saved.
  If Zoom is minimised or on another Space, audio keeps recording, those lines are labelled
  `Not recognised`, and detection resumes by itself when the window is back. Zoom covered by other
  windows should still be detected.
- **Transcription**: free local `whisper.cpp`, or the OpenAI Whisper API. Forced to English with a
  British/Indian-English prompt hint.
- **Notes**: your own Claude or OpenAI key (stored in the Keychain). The model list is fetched live from
  the provider's `/models` endpoint, so new models show up without an app update.
- **Output**: `~/Documents/MeetingNotes/<date time>/notes.md` (Summary, Decisions, Action items,
  Open questions, Detailed notes) and `transcript.md`. Raw audio is deleted once notes are written.

## Setting up on a new Mac

Needs macOS 13 (Ventura) or newer, on Apple Silicon or Intel. Takes about 10 minutes, most of it downloads.

### 1. Install the tools (one time)

```bash
# Swift compiler (skip if Xcode is installed; `swift --version` should work afterwards)
xcode-select --install

# Homebrew (skip if `brew --version` already works)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Free, offline speech-to-text
brew install whisper-cpp
```

### 2. Download the speech model (one time, ~550 MB)

```bash
mkdir -p ~/Library/Application\ Support/MeetingNotes
curl -L -o ~/Library/Application\ Support/MeetingNotes/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

Skip steps 1–2 for whisper if you will use the **OpenAI Whisper API** for transcription instead
(Settings → Transcription); that uploads the audio to OpenAI and needs an OpenAI key.

### 3. Get the code and build the app

```bash
git clone -b claude/zoom-meeting-summary-app-9m0wgv https://github.com/sunny-github69/learn-.git
cd learn-/MeetingNotes
./scripts/build_app.sh                      # creates build/MeetingNotes.app
cp -R build/MeetingNotes.app /Applications/ # needed for "Launch at login"
open /Applications/MeetingNotes.app
```

A waveform icon appears in the menu bar (top right). There is no Dock icon; that is expected.

### 4. Configure

Click the menu-bar icon → ⚙︎:

- **AI notes**: pick Claude or ChatGPT, paste your API key. It is checked live ("Key works · N models")
  and the model list loads; pick a model. Keys are stored in the macOS Keychain, never in files.
  Turn AI notes off to save only the transcript.
- **General**: *Launch at login*, *Auto-record when a Zoom meeting starts*, your name (used instead
  of "You" in the transcript), and *Identify who is speaking*.
- **Transcription**: local whisper.cpp (shows "Model found" if step 2 worked) or the OpenAI API.

The three main switches (auto-record, speakers, AI notes) are also in the menu-bar popover.

### 5. Grant permissions (first recording)

Join a test Zoom meeting and press **Start recording**. macOS asks for:

- **Microphone** → Allow.
- **Screen & System Audio Recording** → open System Settings → Privacy & Security → enable
  *MeetingNotes*. macOS may ask you to quit and reopen the app; do so and start again.

Speak for a minute, press **Stop & write notes**, then **Open**. The files are in
`~/Documents/MeetingNotes/<date time>/`.

### Updating

```bash
cd learn-/MeetingNotes
git pull
./scripts/build_app.sh && rm -rf /Applications/MeetingNotes.app && cp -R build/MeetingNotes.app /Applications/
open /Applications/MeetingNotes.app
```

The app is ad-hoc signed, so macOS treats each build as a new app: if recording fails after an update,
remove *MeetingNotes* from Privacy & Security → Screen & System Audio Recording and Microphone, and
allow it again. Settings and API keys are kept.

### Troubleshooting

| Problem | Fix |
|---|---|
| `swift: command not found` | `xcode-select --install`, then open a new terminal. |
| "whisper-cli not found" | `brew install whisper-cpp` |
| "Whisper model not found" | Redo step 2, or fix the path in Settings → Transcription. |
| Notes have no "Others" lines | Screen & System Audio Recording permission is missing; grant it and reopen the app. |
| Every line is "Not recognised" | Use Zoom's Gallery view and keep the Zoom window visible. |
| "Couldn't change login item" | Move the app to `/Applications` first. |
| API error | Check the key and the account's credit in the Claude / OpenAI console. |

### Uninstall

```bash
rm -rf /Applications/MeetingNotes.app ~/Library/Application\ Support/MeetingNotes
defaults delete com.local.meetingnotes
```
Meeting notes in `~/Documents/MeetingNotes` are left alone.

## How auto-record works

The app watches for Zoom's `CptHost` helper process, which exists only during a meeting: recording
starts when you join and the notes are written when you leave.

## Notes
- Speaker names need Gallery view and the Zoom window visible (not minimised). Speaker view has no
  green border, so those lines fall back to `Not recognised`.
- Start Zoom before recording: then only Zoom's audio is captured. Otherwise it falls back to all system audio
  and speaker names are off.
- Use headphones, otherwise Zoom audio leaks into your mic and gets transcribed twice.
- Recording laws differ by country/state (some require every participant's consent). Check your
  jurisdiction and your company policy before recording without telling people.
