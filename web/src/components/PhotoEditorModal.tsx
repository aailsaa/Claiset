import Cropper, { type Area } from 'react-easy-crop'
import { useEffect, useMemo, useRef, useState } from 'react'
import { cropRotateToPngDataUrl } from '../imageEdit'

type Props = {
  open: boolean
  imageSrc: string | null
  originalSrc: string | null
  onCancel: () => void
  onSave: (dataUrl: string) => void
}

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('Failed to load image'))
    img.crossOrigin = 'anonymous'
    img.src = src
  })
}

function drawCheckerboard(ctx: CanvasRenderingContext2D, w: number, h: number) {
  const size = 12
  for (let y = 0; y < h; y += size) {
    for (let x = 0; x < w; x += size) {
      const odd = ((x / size) ^ (y / size)) & 1
      ctx.fillStyle = odd ? 'rgba(0,0,0,0.06)' : 'rgba(0,0,0,0.02)'
      ctx.fillRect(x, y, size, size)
    }
  }
}

export function PhotoEditorModal({ open, imageSrc, originalSrc, onCancel, onSave }: Props) {
  const [crop, setCrop] = useState({ x: 0, y: 0 })
  const [zoom, setZoom] = useState(1)
  const [rotation, setRotation] = useState(0)
  const [croppedPixels, setCroppedPixels] = useState<Area | null>(null)
  const [saving, setSaving] = useState(false)
  const [tab, setTab] = useState<'crop' | 'refine'>('crop')
  const [brushMode, setBrushMode] = useState<'restore' | 'erase'>('restore')
  const [brushSize, setBrushSize] = useState(22)
  const [workingSrc, setWorkingSrc] = useState<string | null>(null)
  const [loadingRefine, setLoadingRefine] = useState(false)
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const rafRef = useRef<number | null>(null)
  const isPaintingRef = useRef(false)
  const originalDataRef = useRef<ImageData | null>(null)
  const workingDataRef = useRef<ImageData | null>(null)

  useEffect(() => {
    if (!open) return
    setTab('crop')
    setWorkingSrc(imageSrc)
  }, [open, imageSrc])

  const canSave = useMemo(
    () => Boolean(workingSrc && croppedPixels && !saving),
    [workingSrc, croppedPixels, saving],
  )

  useEffect(() => {
    if (!open || tab !== 'refine' || !workingSrc || !originalSrc) return
    let cancelled = false
    setLoadingRefine(true)
    ;(async () => {
      try {
        const [origImg, workImg] = await Promise.all([loadImage(originalSrc), loadImage(workingSrc)])
        if (cancelled) return
        const w = Math.max(1, workImg.naturalWidth || workImg.width)
        const h = Math.max(1, workImg.naturalHeight || workImg.height)
        const canvas = canvasRef.current
        if (!canvas) return
        canvas.width = w
        canvas.height = h
        const ctx = canvas.getContext('2d')
        if (!ctx) return

        // Original
        const oCanvas = document.createElement('canvas')
        oCanvas.width = w
        oCanvas.height = h
        const oCtx = oCanvas.getContext('2d')
        if (!oCtx) return
        oCtx.drawImage(origImg, 0, 0, w, h)
        originalDataRef.current = oCtx.getImageData(0, 0, w, h)

        // Working (foreground with alpha)
        const wCanvas = document.createElement('canvas')
        wCanvas.width = w
        wCanvas.height = h
        const wCtx = wCanvas.getContext('2d')
        if (!wCtx) return
        wCtx.drawImage(workImg, 0, 0, w, h)
        workingDataRef.current = wCtx.getImageData(0, 0, w, h)

        // Initial paint
        drawCheckerboard(ctx, w, h)
        ctx.putImageData(workingDataRef.current, 0, 0)
      } finally {
        if (!cancelled) setLoadingRefine(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [open, tab, workingSrc, originalSrc])

  function scheduleCanvasRedraw() {
    if (rafRef.current != null) return
    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = null
      const canvas = canvasRef.current
      const ctx = canvas?.getContext('2d')
      const data = workingDataRef.current
      if (!canvas || !ctx || !data) return
      drawCheckerboard(ctx, canvas.width, canvas.height)
      ctx.putImageData(data, 0, 0)
    })
  }

  function paintAt(clientX: number, clientY: number) {
    const canvas = canvasRef.current
    const orig = originalDataRef.current
    const work = workingDataRef.current
    if (!canvas || !orig || !work) return
    const rect = canvas.getBoundingClientRect()
    const x = Math.round(((clientX - rect.left) / rect.width) * canvas.width)
    const y = Math.round(((clientY - rect.top) / rect.height) * canvas.height)
    const r = Math.max(4, Math.round(brushSize))
    const w = canvas.width
    const h = canvas.height
    const x0 = Math.max(0, x - r)
    const x1 = Math.min(w - 1, x + r)
    const y0 = Math.max(0, y - r)
    const y1 = Math.min(h - 1, y + r)
    const rr = r * r
    for (let yy = y0; yy <= y1; yy++) {
      const dy = yy - y
      for (let xx = x0; xx <= x1; xx++) {
        const dx = xx - x
        if (dx * dx + dy * dy > rr) continue
        const i = (yy * w + xx) * 4
        if (brushMode === 'erase') {
          work.data[i + 3] = 0
        } else {
          // restore: take original RGB and solid alpha
          work.data[i + 0] = orig.data[i + 0]
          work.data[i + 1] = orig.data[i + 1]
          work.data[i + 2] = orig.data[i + 2]
          work.data[i + 3] = 255
        }
      }
    }
    scheduleCanvasRedraw()
  }

  async function commitRefineToWorkingSrc() {
    const canvas = canvasRef.current
    const data = workingDataRef.current
    if (!canvas || !data) return
    const out = document.createElement('canvas')
    out.width = canvas.width
    out.height = canvas.height
    const ctx = out.getContext('2d')
    if (!ctx) return
    ctx.putImageData(data, 0, 0)
    setWorkingSrc(out.toDataURL('image/png'))
  }

  if (!open || !imageSrc) return null

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center" role="dialog" aria-modal="true">
      <div className="w-full max-w-2xl overflow-hidden rounded-3xl border border-[var(--color-line)] bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-[var(--color-line)] px-5 py-4">
          <h3 className="text-sm font-semibold text-[var(--color-ink)]">Edit photo</h3>
          <button type="button" onClick={onCancel} className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-paper)]">
            Close
          </button>
        </div>

        <div className="border-b border-[var(--color-line)] px-5 py-3">
          <div className="flex items-center gap-2 rounded-2xl bg-[var(--color-paper)]/60 p-1">
            <button
              type="button"
              onClick={() => setTab('crop')}
              className={`flex-1 rounded-xl px-3 py-2 text-sm font-semibold transition ${
                tab === 'crop'
                  ? 'bg-white text-[var(--color-ink)] shadow-sm'
                  : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
              }`}
            >
              Crop
            </button>
            <button
              type="button"
              onClick={() => setTab('refine')}
              className={`flex-1 rounded-xl px-3 py-2 text-sm font-semibold transition ${
                tab === 'refine'
                  ? 'bg-white text-[var(--color-ink)] shadow-sm'
                  : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
              }`}
            >
              Refine
            </button>
          </div>
        </div>

        <div className="grid gap-4 p-5 sm:grid-cols-[minmax(0,1fr)_260px]">
          <div className="relative aspect-[4/3] overflow-hidden rounded-2xl bg-[var(--color-paper)]">
            {tab === 'crop' ? (
              <Cropper
                image={workingSrc ?? imageSrc}
                crop={crop}
                zoom={zoom}
                rotation={rotation}
                aspect={1}
                onCropChange={setCrop}
                onRotationChange={setRotation}
                onZoomChange={setZoom}
                onCropComplete={(_, areaPixels) => setCroppedPixels(areaPixels)}
                objectFit="contain"
                showGrid={false}
              />
            ) : (
              <div className="relative h-full w-full">
                <canvas
                  ref={canvasRef}
                  className="h-full w-full touch-none"
                  onPointerDown={(e) => {
                    isPaintingRef.current = true
                    ;(e.currentTarget as HTMLCanvasElement).setPointerCapture(e.pointerId)
                    paintAt(e.clientX, e.clientY)
                  }}
                  onPointerMove={(e) => {
                    if (!isPaintingRef.current) return
                    paintAt(e.clientX, e.clientY)
                  }}
                  onPointerUp={async () => {
                    isPaintingRef.current = false
                    await commitRefineToWorkingSrc()
                  }}
                  onPointerCancel={() => {
                    isPaintingRef.current = false
                  }}
                />
                {loadingRefine ? (
                  <div className="absolute inset-0 flex items-center justify-center text-sm font-semibold text-[var(--color-muted)]">
                    Preparing editor…
                  </div>
                ) : null}
              </div>
            )}
          </div>

          <div className="space-y-4">
            {tab === 'crop' ? (
              <>
                <label className="block text-xs font-medium text-[var(--color-muted)]">
                  Zoom
                  <input
                    type="range"
                    min={1}
                    max={3}
                    step={0.01}
                    value={zoom}
                    onChange={(e) => setZoom(Number(e.target.value))}
                    className="mt-2 w-full"
                  />
                </label>
                <label className="block text-xs font-medium text-[var(--color-muted)]">
                  Rotate
                  <input
                    type="range"
                    min={-180}
                    max={180}
                    step={1}
                    value={rotation}
                    onChange={(e) => setRotation(Number(e.target.value))}
                    className="mt-2 w-full"
                  />
                </label>
              </>
            ) : (
              <>
                <div className="rounded-2xl border border-[var(--color-line)] bg-white p-4">
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() => setBrushMode('restore')}
                      className={`flex-1 rounded-full px-4 py-2 text-sm font-semibold ring-1 ${
                        brushMode === 'restore'
                          ? 'bg-[var(--color-sage)] text-white ring-[var(--color-sage)]'
                          : 'bg-white text-[var(--color-ink)] ring-[var(--color-line)] hover:bg-[var(--color-paper)]'
                      }`}
                    >
                      Restore
                    </button>
                    <button
                      type="button"
                      onClick={() => setBrushMode('erase')}
                      className={`flex-1 rounded-full px-4 py-2 text-sm font-semibold ring-1 ${
                        brushMode === 'erase'
                          ? 'bg-[var(--color-clay)] text-white ring-[var(--color-clay)]'
                          : 'bg-white text-[var(--color-ink)] ring-[var(--color-line)] hover:bg-[var(--color-paper)]'
                      }`}
                    >
                      Erase
                    </button>
                  </div>
                  <label className="mt-4 block text-xs font-medium text-[var(--color-muted)]">
                    Brush size
                    <input
                      type="range"
                      min={6}
                      max={60}
                      step={1}
                      value={brushSize}
                      onChange={(e) => setBrushSize(Number(e.target.value))}
                      className="mt-2 w-full"
                    />
                  </label>
                </div>
                <p className="text-xs text-[var(--color-muted)]">
                  Use <span className="font-semibold">Restore</span> to fill holes in the item. Use{' '}
                  <span className="font-semibold">Erase</span> to remove leftover background.
                </p>
              </>
            )}

            <div className="flex gap-2 pt-2">
              <button
                type="button"
                onClick={onCancel}
                className="flex-1 rounded-full border border-[var(--color-line)] py-2.5 text-sm font-semibold text-[var(--color-muted)]"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={!canSave}
                onClick={async () => {
                  const src = workingSrc ?? imageSrc
                  if (!src || !croppedPixels) return
                  setSaving(true)
                  try {
                    const dataUrl = await cropRotateToPngDataUrl({
                      imageSrc: src,
                      crop: croppedPixels,
                      rotationDeg: rotation,
                    })
                    onSave(dataUrl)
                  } finally {
                    setSaving(false)
                  }
                }}
                className="flex-1 rounded-full bg-[var(--color-clay)] py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-60"
              >
                {saving ? 'Saving…' : 'Save'}
              </button>
            </div>

            <p className="text-xs text-[var(--color-muted)]">
              Tip: If the sweater has holes, use Refine → Restore before saving.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}

