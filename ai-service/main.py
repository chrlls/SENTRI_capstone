"""
SENTRI AI Microservice — Voice Distress Classification

Wraps the binary distress classifier (final_model_v2, fine-tuned XLSR-53)
behind a narrow HTTP contract. This service is intentionally "dumb" about
everything except classification:

  - It does NOT know about incident_id, user_id, or any SENTRI business
    logic — Laravel owns that. This service receives audio, returns a
    classification, and forgets the request existed.
  - It does NOT fetch audio from storage — Laravel forwards raw bytes.
    No storage credentials live here. See DESIGN_DECISIONS.md ("How audio
    gets to FastAPI") for the reasoning.
  - It is called SYNCHRONOUSLY by Laravel, which enforces its own timeout
    and fallback behavior. This service does not implement retries,
    queues, or callbacks — if it can't answer fast, that's a Laravel-side
    concern, not this service's.

Model loading: MOCK_MODE (env var) swaps the real model for a
deterministic mock so the contract can be tested without final_model_v2
present. Swap load_model()/run_inference() for the real thing when this
moves to the machine that actually has the model weights.
"""

import io
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, File, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sentri-ai-service")

MODEL_VERSION = "final_model_v2"
MOCK_MODE = os.getenv("SENTRI_MOCK_MODE", "true").lower() == "true"

# Accepted audio content types. Reject anything else early rather than
# passing garbage into the model.
ALLOWED_CONTENT_TYPES = {
    "audio/wav", "audio/x-wav", "audio/wave",
    "audio/mpeg", "audio/mp3",
    "audio/mp4", "audio/m4a", "audio/x-m4a",
    "audio/ogg", "audio/webm",
}

# Reject absurdly large uploads before they hit the model. Distress clips
# are short (seconds), so this is generous, not tight.
MAX_AUDIO_BYTES = 10 * 1024 * 1024  # 10 MB


# ============================================================================
# Model loading
# ============================================================================

class ModelState:
    """Holds the loaded model so it's read once at startup, not per-request."""
    model = None
    processor = None
    loaded = False


model_state = ModelState()


def load_model() -> None:
    """
    Load final_model_v2 once at service startup.

    MOCK MODE: no-op, marks loaded=True immediately.

    REAL MODE: final_model_v2 is a Wav2Vec2ForSequenceClassification with no
    tokenizer (no vocab.json), so it uses Wav2Vec2FeatureExtractor, not the
    full Wav2Vec2Processor (which would fail loading a nonexistent
    tokenizer).
    """
    if MOCK_MODE:
        logger.info("MOCK_MODE=true — skipping real model load.")
        model_state.loaded = True
        return

    from transformers import Wav2Vec2FeatureExtractor, Wav2Vec2ForSequenceClassification

    model_path = os.environ["SENTRI_MODEL_PATH"]  # fail loudly if unset
    model_state.processor = Wav2Vec2FeatureExtractor.from_pretrained(model_path)
    model_state.model = Wav2Vec2ForSequenceClassification.from_pretrained(model_path)
    model_state.model.eval()
    model_state.loaded = True


def run_inference(audio_bytes: bytes) -> tuple[bool, float]:
    """
    Run the classifier on raw audio bytes.
    Returns (distress_label, distress_confidence).

    MOCK MODE: deterministic-ish fake result based on byte length, purely
    so the contract/response shape can be exercised end-to-end. Not a real
    classification signal — do not read anything into the fake numbers.

    REAL MODE: id2label in config.json confirms index 1 = "distress".
    """
    if MOCK_MODE:
        # Deterministic fake: longer clips skew toward "distress" so you can
        # exercise both branches by varying test file size. Not meaningful.
        pseudo_score = min(0.95, 0.2 + (len(audio_bytes) % 1000) / 1000)
        label = pseudo_score >= 0.5
        return label, round(pseudo_score, 3)

    import torch
    import torchaudio

    waveform, sr = torchaudio.load(io.BytesIO(audio_bytes))
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    if sr != 16000:
        waveform = torchaudio.functional.resample(waveform, sr, 16000)

    inputs = model_state.processor(
        waveform.squeeze().numpy(), sampling_rate=16000, return_tensors="pt"
    )
    with torch.no_grad():
        logits = model_state.model(**inputs).logits
        probs = torch.softmax(logits, dim=-1)
    distress_confidence = float(probs[0][1])  # index 1 = distress class
    distress_label = distress_confidence >= 0.5
    return distress_label, round(distress_confidence, 3)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Loading model (MOCK_MODE=%s)...", MOCK_MODE)
    load_model()
    logger.info("Model ready.")
    yield
    logger.info("Shutting down.")


app = FastAPI(
    title="SENTRI AI Microservice",
    description="Binary voice distress classification for SENTRI incidents.",
    version="1.0.0",
    lifespan=lifespan,
)


# ============================================================================
# Schemas
# ============================================================================

class DistressClassificationResponse(BaseModel):
    distress_label: bool = Field(..., description="True if distress detected")
    distress_confidence: float = Field(..., ge=0, le=1, description="Confidence 0-1")
    model_version: str = Field(default=MODEL_VERSION)
    inference_ms: int = Field(..., description="Server-side inference time, for Laravel timeout tuning")


class ErrorResponse(BaseModel):
    error: str
    detail: str


class HealthResponse(BaseModel):
    status: str
    model_version: str
    mock_mode: bool


# ============================================================================
# Routes
# ============================================================================

@app.get("/health", response_model=HealthResponse)
async def health():
    """
    Laravel should hit this on its own startup / periodically, NOT per
    inference request — keep the hot path (POST /classify) free of
    extra checks beyond what's needed per request.
    """
    return HealthResponse(
        status="ok" if model_state.loaded else "model_not_loaded",
        model_version=MODEL_VERSION,
        mock_mode=MOCK_MODE,
    )


@app.post(
    "/classify",
    response_model=DistressClassificationResponse,
    responses={
        400: {"model": ErrorResponse, "description": "Invalid/unsupported audio"},
        413: {"model": ErrorResponse, "description": "Audio file too large"},
        500: {"model": ErrorResponse, "description": "Inference failure"},
        503: {"model": ErrorResponse, "description": "Model not ready"},
    },
)
async def classify(audio: UploadFile = File(...)):
    """
    Classify a single audio clip for distress.

    Laravel calls this SYNCHRONOUSLY and should apply its own timeout
    (recommend 5-10s). On timeout or any non-200 response, Laravel's
    documented fallback is: treat as AI-inconclusive, do NOT block or
    delay the incident — manual/keyword triggers proceed independently.
    This service has no opinion on that fallback; it just answers or
    fails fast.
    """
    if not model_state.loaded:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Model not loaded yet.",
        )

    if audio.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported content type: {audio.content_type}",
        )

    raw = await audio.read()

    if len(raw) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty audio file.",
        )

    if len(raw) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Audio exceeds {MAX_AUDIO_BYTES} byte limit.",
        )

    start = time.monotonic()
    try:
        label, confidence = run_inference(raw)
    except Exception:
        logger.exception("Inference failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Inference failed.",
        )
    elapsed_ms = int((time.monotonic() - start) * 1000)

    logger.info(
        "Classified clip: label=%s confidence=%.3f elapsed_ms=%d size_bytes=%d",
        label, confidence, elapsed_ms, len(raw),
    )

    return DistressClassificationResponse(
        distress_label=label,
        distress_confidence=confidence,
        model_version=MODEL_VERSION,
        inference_ms=elapsed_ms,
    )
