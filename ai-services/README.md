# SENTRI AI Microservice

Binary voice distress classification, wrapping `final_model_v2`. Called
synchronously by Laravel — see `DESIGN_DECISIONS.md` in the Obsidian vault
for the full sync-vs-async and audio-transport reasoning.

## Contract summary

- **Endpoint:** `POST /classify`
- **Input:** `multipart/form-data`, field name `audio`, raw audio bytes
  (wav/mp3/m4a/ogg/webm). Max 10 MB.
- **Output (200):**
  ```json
  {
    "distress_label": true,
    "distress_confidence": 0.812,
    "model_version": "final_model_v2",
    "inference_ms": 340
  }
  ```
  Maps directly to `voice_analysis_events.distress_label`,
  `.distress_confidence`, `.model_version`.
- **Errors:** 400 (bad/empty/unsupported audio), 413 (too large),
  500 (inference failure), 503 (model not loaded). Laravel should treat
  ANY non-200 (including timeout) as "AI inconclusive" and proceed with
  the incident regardless — never block on this service.
- **Health check:** `GET /health` — call at Laravel startup, not per
  inference request.

## Running locally (mock mode — no model file needed)

```bash
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

`SENTRI_MOCK_MODE` defaults to `true`, which returns a fake-but-valid
classification so you can test the contract, Laravel's HTTP client code,
and its timeout/fallback behavior before the real model is wired in.

## Swapping in the real model (do this in VS Code, not this sandbox)

1. Get `final_model_v2` onto the machine running this service (from your
   Drive backup). It's a `Wav2Vec2ForSequenceClassification` with no
   tokenizer — `load_model()` uses `Wav2Vec2FeatureExtractor`, not the
   full `Wav2Vec2Processor`.
2. `pip install -r requirements.txt` (torch/torchaudio/transformers are
   already uncommented).
3. Install system FFmpeg and put it on `PATH` — `torchaudio.load()`
   decodes via the `torchcodec` package, which requires FFmpeg's shared
   libraries to decode anything (wav/mp3/m4a/ogg/webm all go through it).
   On Windows: `winget install Gyan.FFmpeg.Shared` (must be the
   **Shared** variant — the plain `Gyan.FFmpeg` build is static and does
   not ship the DLLs torchcodec needs).
4. Set `SENTRI_MODEL_PATH` to the model directory and
   `SENTRI_MOCK_MODE=false` when starting the service, e.g.:
   ```bash
   SENTRI_MODEL_PATH=/path/to/final_model_v2 SENTRI_MOCK_MODE=false \
     uvicorn main:app --host 0.0.0.0 --port 8000
   ```
5. Re-run the same curl tests from this session (see chat history / your
   own notes) against the real model to confirm the contract still holds
   with real weights — same requests, same expected response shape, just
   real numbers instead of mock ones.

## What this service deliberately does NOT do

- Does not know about `incident_id` or `user_id` — stateless, single
  responsibility (audio in, classification out).
- Does not fetch audio from storage — only accepts what's POSTed to it.
- Does not retry, queue, or call back — synchronous request/response only.
- Does not write to the database — Laravel owns the `voice_analysis_events`
  insert after receiving this service's response.

These boundaries are deliberate, not omissions — see
`DESIGN_DECISIONS.md` if reconsidering any of them.
