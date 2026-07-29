# TTS integration

The demo supports asynchronous text-to-speech through the ECNU OpenAI-compatible
speech endpoint:

```text
POST https://chat.ecnu.edu.cn/open/api/v1/audio/speech
model: ecnu-tts
voice: xiayu | liwa
response_format: mp3
```

Runtime flow:

```text
AI speech
  -> MessageBus.route_agent_output()
  -> MessageBus.tts_speech_requested
  -> TTSService
  -> ECNU TTS mp3 response
  -> AudioStreamMP3 playback
```

Enable it in `data/llm_config.json`:

```json
{
  "tts": {
    "enabled": true,
    "api_url": "https://chat.ecnu.edu.cn/open/api/v1/audio/speech",
    "api_key": "YOUR_API_KEY_HERE",
    "model": "ecnu-tts",
    "voice": "liwa",
    "response_format": "mp3",
    "speed": 1.0,
    "interrupt_current": true
  }
}
```

If `tts.api_key` is omitted, `TTSService` falls back to the top-level `api_key` in
`llm_config.json`, which is convenient when chat and TTS share the same ECNU token.

## About streaming

The documented ECNU endpoint returns one complete binary audio response per request.
It does not expose a chunked streaming protocol in the provided documentation.

To keep the UI responsive, `TTSService` implements near-streaming behavior:

- long text is split by sentence punctuation;
- the first chunk starts playing as soon as its mp3 response arrives;
- later chunks continue through the same queue.

## Story timing (`v0.8.13`)

When TTS is configured and enabled, `StoryDirector` asks `TTSService` for a
conservative duration estimate based on non-whitespace character count and
`tts.speed`. A dialogue Beat holds its camera for at least that estimate. When
TTS is disabled, the authored `pause_after` remains unchanged.

This is presentation timing rather than sample-accurate lip sync: the documented
ECNU response contains a complete MP3 and no word timestamps or streaming
playback events. A future PCM/timestamp endpoint can replace the estimate behind
the same director contract.

True realtime streaming would require a TTS endpoint that returns playable PCM/opus
chunks progressively, or a small local service that can request/chunk/cache audio and
feed Godot incrementally.
