# HAVEN — The 911 you can't call

**Offline emergency aid powered by on-device Gemma 4 (E2B / LiteRT-LM)**

**Tracks:** Main Track · Impact: Global Resilience · Special Tech: LiteRT

---

## The 911 you can't call

War zones share a brutal pattern: the moment people need information the most — air raid sirens, an injury, blocked roads, jammed networks — is the moment information stops flowing. Cellular gets jammed or blacked out. Hospital lines saturate. Cloud-hosted AI assistants are useless without a connection, and the assumption that someone is sitting at a keyboard to type a query feels naive when you're hurt or hiding in a basement.

HAVEN is built around the opposite assumption: the model lives entirely on the phone, the city's map and recent news are pre-cached, and the user can speak to it in their own language without lifting a hand from a wound. It's an emergency aid app whose AI never needs to call home.

## What HAVEN is

A Flutter iPhone/Android app with four tabs:

- **Map** — offline OSM tiles, 100 hand-curated Tehran POIs (hospitals, embassies, shelters, schools, fuel, transit) layered with whatever Overpass returns at refresh time, magnetometer-driven compass.
- **Newspaper** — cached local reports from Google News RSS, GDELT, and GDACS with extracted article bodies; tap any source URL to open in the system browser.
- **Agent** — on-device Gemma 4 E2B chat with voice in/out, six native-function-calling tools, and tool→UI navigation cards.
- **Settings** — survival manuals, news-source toggles, and a **Location preset chooser** (Tehran / Kyiv / Gaza / *Use my real GPS*).

Everything in the Agent tab — prompts, responses, cached context, function calls, voice — happens locally on the phone. No prompt, no response, no cached headline, and no user query ever leaves the device.

### Why Tehran, and why it isn't hardcoded

The app opens in **Tehran, Iran** by default — the most concrete current war-context narrative for the demo: active conflict, daily news, dense urban POIs, and a multilingual user base. The 100 bundled POIs are Tehran-anchored for the same reason.

But Tehran is a **default, not a hardcode**. Settings → *Demo Location* re-anchors the entire app to **Kyiv, Ukraine** (armed conflict), **Gaza City, Palestine** (humanitarian crisis), or **Use my real GPS** (Geolocator + reverse-geocoded labels, with a Tehran fallback if permission is denied). Switching the preset triggers map re-fetch + Newspaper repull + Agent context rebuild in one tap — the difference between *"a demo that only works in one city"* and *"a real tool with a strong demo default"*.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter UI                                                 │
│  Map · Newspaper · Agent (chat + voice) · Settings          │
└──────────┬──────────────────────────────────┬───────────────┘
           │                                  │
   ┌───────▼──────────┐                ┌──────▼───────────┐
   │ flutter_gemma    │                │ Hive on-disk     │
   │ 0.15 + Dart FFI  │                │ cache            │
   │ to LiteRT-LM     │                │  · news          │
   └───────┬──────────┘                │  · safe places   │
           │                           │  · manuals       │
           ▼                           │  · settings      │
   ┌────────────────────┐              └──────────────────┘
   │ LiteRT-LM SDK      │
   │ (Google AI Edge)   │
   └─────────┬──────────┘
             │
   ┌─────────▼────────────────┐
   │ Metal (iOS) · OpenCL     │
   │ (Android) · CPU fallback │
   └──────────────────────────┘
```

Network calls only happen at refresh time: news endpoints, Overpass with two mirror fallbacks for safe places, OSRM for routes. After one successful online refresh, every map marker, every headline, and every manual step is on disk. The Gemma 4 weights themselves (~1.5 GB `.litertlm`) download once on first launch, gated by a HuggingFace token loaded from a gitignored `.env`.

## How HAVEN uses Gemma 4

### Native function calling (six tools)

We declare six locally-executed tools in `ai_tools_service.dart` with JSON-schema parameters:

| Tool | Purpose |
|---|---|
| `get_safe_places(category?, max?)` | List cached POIs by category |
| `find_nearest(category)` | Single closest match |
| `get_news_article(query)` | Full body of one cached article |
| `summarize_news(topic, max?)` | Multi-source distillation |
| `assess_current_risks()` | Keyword scan over headlines |
| `get_manual_steps(manual_id)` | Full survival manual content |

All run against the local Hive cache, never the network. When the chat stream emits a `FunctionCallResponse`, we dispatch the tool, send the JSON result back as a `Message.toolResponse`, and resume generation. Capped at four iterations to prevent runaway loops.

The user-visible payoff: ask *"where is the nearest hospital?"* and the model emits `find_nearest(category: "hospital")`, we hand back a real Tehran address, and a tappable card appears in the chat — *"Show Tehran Heart Center on map"* — that switches to the Map tab pre-filtered to hospitals. The agent commands the rest of the app, not just the chat bubble.

### Multilingual

Gemma 4 is multilingual out of the box. Our system instruction explicitly nudges:

> ALWAYS respond in the user's input language. If they write in Persian (فارسی), reply in Persian. If they write in Korean (한국어), reply in Korean.

A user in Tehran can ask in Persian and get Persian back, citing cached local data. The compact system context (location + 8 headlines + 8 safe-place names + manual titles — ~700 tokens total) is set once at chat creation so it lives in the KV cache instead of being re-transmitted per turn. Without this discipline we were crashing the simulator at turn three from KV-cache blowup.

### Voice in / voice out

The mic is a push-to-talk pill (*HOLD TO TALK*) wired through `speech_to_text`. TTS readback runs `flutter_tts` and auto-detects Persian / Korean / English script per reply, switching the OS voice accordingly. A one-time silent prime utterance activates the iOS `AVAudioSession` at app start so the very first TTS reply is audible without requiring a prior mic interaction — a known iOS quirk that took us a day to track down.

### Proactive situation read

The first thing the user sees in the Agent tab is a synthetic first turn the app fires automatically the moment the Gemma session is ready: *"Top risks today / Nearest safe places / Most relevant manual"*, three bullets, grounded in the cached context. No typing required. This is the "agentic retrieval" the hackathon brief names.

## LiteRT-LM integration

HAVEN is built on **Google AI Edge's LiteRT-LM SDK** end-to-end. We use the `.litertlm` weights published by `litert-community/gemma-4-E2B-it-litert-lm`, loaded through `flutter_gemma 0.15`'s LiteRT-LM FFI client (`LiteRtLmFfiClient.initialize`). Accelerator selection comes directly from LiteRT's registry: Metal on iOS, OpenCL on Android, with automatic CPU fallback if the GPU path errors at init — so a Metal driver quirk on one device class doesn't take the agent offline.

Native function calling routes through LiteRT-LM's `tools_json` mechanism rather than regex-parsing the model output; the SDK separates `<|tool_call>…<tool_call|>` blocks from natural-language tokens, which we surface as `FunctionCallResponse` events in the chat stream.

Every completed reply shows an inference perf chip: *"12.4 tok/s · GPU(Metal) via LiteRT-LM"* — measured from first-token to stream-done, prefill excluded. On an iPhone 16e the GPU path holds ~10–15 tok/s; the CPU fallback is ~2 tok/s — still usable in a pinch and lifesaving when the GPU path is unavailable.

## Challenges we hit (and what we did about them)

- **iOS Simulator Metal binding limit.** The simulator's Metal driver doesn't support Argument Buffers Tier 2, capping texture-binding index at 30. Gemma 4's prefill shader needs binding 31. We added explicit GPU → CPU fallback plus an in-app diagnostic that shows both errors so a corrupt file is distinguishable from an incompatible host.
- **KV cache blowup at turn 3–4.** We were re-injecting the cached context with every user message, ballooning history past `maxTokens` and crashing the simulator. Moved the static context into `systemInstruction` (sent once, stays in the KV cache), bumped `maxTokens` 2048 → 4096, added a Reset Chat button on the status banner.
- **AVAudioSession lazy activation.** TTS was silent until the mic was used once. iOS doesn't activate the session until *something* asks. Fix: a single inaudible-whitespace TTS call at session prep to prime the audio session.
- **Overpass rate-limiting.** Public Overpass throttles certain regions; refresh would silently return zero results. We bundled 100 hand-curated Tehran POIs into the binary so the map always has data, plus added a three-mirror endpoint fallback (`overpass-api.de` → `kumi.systems` → `openstreetmap.fr`) for fresh pulls.
- **Tool-call echoes leaking into the chat.** The LiteRT-LM SDK normally parses `<|tool_call>` blocks before they reach Dart, but occasionally a fragment slipped through as plain `TextResponse`. Added a per-turn echo filter that detects the start of a tool-call JSON blob and drops every subsequent token for the rest of that turn.

## What's next

An Unsloth fine-tune on FEMA / WHO / ICRC corpora (targeting the **Unsloth Special Tech** track) and an E4B vision upgrade so users can photograph an injury and get an assessment. The architecture is wired for both — `LocalAgentService` abstracts the model identity; function calling just gains new vision-aware tools. New `LocationPreset` cities are one enum value away.

---

**Repo:** https://github.com/lucascho00/haven
**Video:** *(YouTube link)*
**Live demo:** *(TestFlight build link)*
