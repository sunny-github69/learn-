# MeetingNotes

A light menu-bar Mac app that records a Zoom meeting **locally** and writes summary + long notes.
It does not join the call as a bot, so Zoom shows nothing to other participants.

- **Others' audio**: captured from the Zoom app only (ScreenCaptureKit). **Your voice**: microphone.
- **Who said what**: in Zoom's Gallery view the active speaker gets a green border. About once a second
  the app finds that border in the Zoom window and reads the name label with on-device OCR (Vision),
  so the transcript says `Albert Dow:` instead of `Others:`. Frames are never saved.
  If Zoom is minimised or on another Space, audio keeps recording, those lines are labelled
  `Not recognised`, and detection resumes by itself when the window is back. Zoom covered by other
  windows still works.
- **Transcription**: free local `whisper.cpp`, or the OpenAI Whisper API. Forced to English with a
  British/Indian-English prompt hint.
- **Notes**: your own Claude or OpenAI key (stored in the Keychain). The model list is fetched live from
  the provider's `/models` endpoint, so new models show up without an app update.
- **Output**: `~/Documents/MeetingNotes/<date time>/notes.md` (Summary, Decisions, Action items,
  Open questions, Detailed notes) and `transcript.md`. Raw audio is deleted once notes are written.

## Setup (macOS 13+)

```bash
xcode-select --install                 # if you have no Swift toolchain
brew install whisper-cpp               # free local transcription
mkdir -p ~/Library/Application\ Support/MeetingNotes
curl -L -o ~/Library/Application\ Support/MeetingNotes/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
./scripts/build_app.sh && open build/MeetingNotes.app
```

Then: menu-bar icon → ⚙︎ → **AI notes** tab → pick provider, paste API key (it is checked live and the
model list loads), pick model. The **General** tab has *Launch at login*, *Auto-record*, your name and
speaker detection; the same switches are in the menu-bar popover. For *Launch at login*, move
`MeetingNotes.app` to `/Applications` first.
Grant **Screen & System Audio Recording** and **Microphone** when macOS asks (re-grant after a rebuild,
since the app is ad-hoc signed).

Turn on **Auto-record Zoom meetings** to avoid pressing anything: the app watches for
Zoom's `CptHost` helper process, which exists only during a meeting.

## Notes
- Speaker names need Gallery view and the Zoom window visible (not minimised). Speaker view has no
  green border, so those lines fall back to `Not recognised`.
- Only recording while Zoom is running captures Zoom-only audio; otherwise it falls back to all system audio.
- Use headphones, otherwise Zoom audio leaks into your mic and gets transcribed twice.
- Recording laws differ by country/state (some require every participant's consent). Check your
  jurisdiction and your company policy before recording without telling people.
