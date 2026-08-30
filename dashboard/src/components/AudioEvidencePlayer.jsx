import { useEffect, useRef, useState } from 'react'
import { Pause, Play } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { apiRequest } from '@/lib/api'
import { formatElapsed, cn } from '@/lib/utils'

const WAVEFORM_BUCKETS = 44

/**
 * Downsamples decoded PCM into per-bucket peak amplitudes for a static
 * waveform, then normalizes so the loudest bucket reaches 1.0 — otherwise
 * a quiet clip renders as a near-flat line.
 */
function computePeaks(audioBuffer, bucketCount) {
  const channelData = audioBuffer.getChannelData(0)
  const samplesPerBucket = Math.max(1, Math.floor(channelData.length / bucketCount))
  const peaks = []

  for (let i = 0; i < bucketCount; i++) {
    let max = 0
    const start = i * samplesPerBucket
    const end = Math.min(start + samplesPerBucket, channelData.length)
    for (let j = start; j < end; j++) {
      const value = Math.abs(channelData[j])
      if (value > max) {
        max = value
      }
    }
    peaks.push(max)
  }

  const loudest = Math.max(...peaks, 0.0001)
  return peaks.map((peak) => peak / loudest)
}

/**
 * Client-side waveform + real duration via the Web Audio API, not
 * server-side amplitude generation — decided in Phase 4: the streaming
 * route (Phase 2) is confirmed working and auth-gated the same way as the
 * incident itself, so decoding in-browser avoids new backend work for a
 * capstone timeline. It also solves the audio_duration_seconds gap Phase 2
 * found (the column is never populated) by reading the real duration off
 * the decoded buffer instead — never displaying the stored, always-null
 * column value.
 *
 * Fetches the clip once via apiRequest() (the same CSRF/cookie-aware
 * fetch every other authenticated call in this app uses) rather than a
 * plain <audio src="..."> pointed at the cross-origin endpoint — a media
 * element only sends credentials cross-origin with
 * crossOrigin="use-credentials" wired up, and even then can't be fed into
 * the Web Audio API for a waveform without a second fetch. One fetch's
 * ArrayBuffer instead feeds both a decodeAudioData() call (waveform +
 * duration) and a Blob object URL (playback), and is safe to fetch once
 * even though this project is capstone-scale, not something exercised at
 * a rate where a second cheap GET would matter.
 */
export function AudioEvidencePlayer({ incidentId }) {
  const audioRef = useRef(null)
  const [status, setStatus] = useState('loading') // loading | ready | error
  const [peaks, setPeaks] = useState([])
  const [duration, setDuration] = useState(null)
  const [currentTime, setCurrentTime] = useState(0)
  const [isPlaying, setIsPlaying] = useState(false)
  const [audioSrc, setAudioSrc] = useState(null)

  useEffect(() => {
    let cancelled = false
    let objectUrl = null

    async function load() {
      try {
        const response = await apiRequest(`/api/incidents/${incidentId}/audio`)
        if (!response.ok) {
          throw new Error(`Audio fetch failed (${response.status})`)
        }

        const arrayBuffer = await response.arrayBuffer()
        if (cancelled) {
          return
        }

        const AudioContextClass = window.AudioContext ?? window.webkitAudioContext
        const audioContext = new AudioContextClass()
        // decodeAudioData may detach its input in some browsers — decode a
        // copy so the original bytes stay intact for the Blob below.
        const decoded = await audioContext.decodeAudioData(arrayBuffer.slice(0))
        await audioContext.close()
        if (cancelled) {
          return
        }

        setPeaks(computePeaks(decoded, WAVEFORM_BUCKETS))
        setDuration(decoded.duration)

        const blob = new Blob([arrayBuffer], { type: response.headers.get('content-type') ?? 'audio/wav' })
        objectUrl = URL.createObjectURL(blob)
        // Set declaratively (src state -> <audio src={audioSrc}>), not via
        // audioRef.current.src — the <audio> element only mounts once
        // status flips to 'ready' (the 'loading' branch renders a plain
        // div instead), so the ref would still be null at this point and
        // the imperative assignment would silently do nothing, leaving a
        // real, mounted <audio> element with an empty src forever.
        setAudioSrc(objectUrl)
        setStatus('ready')
      } catch {
        if (!cancelled) {
          setStatus('error')
        }
      }
    }

    load()

    return () => {
      cancelled = true
      if (objectUrl) {
        URL.revokeObjectURL(objectUrl)
      }
    }
  }, [incidentId])

  function togglePlay() {
    const audio = audioRef.current
    if (audio === null) {
      return
    }
    if (audio.paused) {
      audio.play()
    } else {
      audio.pause()
    }
  }

  function seekToBucket(bucketIndex) {
    const audio = audioRef.current
    if (audio === null || duration === null) {
      return
    }
    audio.currentTime = ((bucketIndex + 0.5) / WAVEFORM_BUCKETS) * duration
  }

  if (status === 'loading') {
    return <div className="flex h-10 items-center text-xs text-muted-foreground">Loading audio…</div>
  }

  if (status === 'error') {
    return <div className="flex h-10 items-center text-xs text-destructive">Audio evidence unavailable.</div>
  }

  const progressRatio = duration ? currentTime / duration : 0

  return (
    <div className="flex items-center gap-2">
      <audio
        ref={audioRef}
        src={audioSrc}
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        onEnded={() => setIsPlaying(false)}
        onTimeUpdate={(event) => setCurrentTime(event.currentTarget.currentTime)}
      />

      <Button
        type="button"
        size="icon"
        variant="outline"
        onClick={togglePlay}
        aria-label={isPlaying ? 'Pause audio evidence' : 'Play audio evidence'}
      >
        {isPlaying ? <Pause className="size-3.5" /> : <Play className="size-3.5" />}
      </Button>

      <div className="flex h-8 flex-1 items-end gap-[2px]" role="presentation">
        {peaks.map((peak, index) => (
          <button
            key={index}
            type="button"
            onClick={() => seekToBucket(index)}
            aria-label={`Seek audio to ${formatElapsed(Math.round(((index + 0.5) / WAVEFORM_BUCKETS) * (duration ?? 0)))}`}
            className={cn(
              'min-h-[3px] flex-1 rounded-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:ring-offset-background',
              index / peaks.length <= progressRatio ? 'bg-purple-400' : 'bg-muted-foreground/40'
            )}
            style={{ height: `${Math.max(peak * 100, 10)}%` }}
          />
        ))}
      </div>

      <span className="font-mono text-[11px] text-muted-foreground tabular-nums">
        {formatElapsed(Math.floor(currentTime))} / {duration === null ? '—:—' : formatElapsed(Math.floor(duration))}
      </span>
    </div>
  )
}
