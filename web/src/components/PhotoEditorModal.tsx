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
  ctx.clearRect(0, 0, w, h)
  const size = 12
  for (let y = 0; y < h; y += size) {
    for (let x = 0; x < w; x += size) {
      const odd = ((x / size) ^ (y / size)) & 1
      // Use opaque colors so repeated redraws don't "darken" via alpha stacking.
      ctx.fillStyle = odd ? '#eef0f2' : '#f8f9fa'
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
  const [refineZoom, setRefineZoom] = useState(1)
  const [refineCenter, setRefineCenter] = useState<{ x: number; y: number }>({ x: 0, y: 0 })
  const [workingSrc, setWorkingSrc] = useState<string | null>(null)
  const [loadingRefine, setLoadingRefine] = useState(false)
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const refineHostRef = useRef<HTMLDivElement | null>(null)
  const rafRef = useRef<number | null>(null)
  const isPaintingRef = useRef(false)
  const originalDataRef = useRef<ImageData | null>(null)
  const workingDataRef = useRef<ImageData | null>(null)
  const offscreenRef = useRef<HTMLCanvasElement | null>(null)
  const viewRef = useRef<{ scale: number; ox: number; oy: number; w: number; h: number; dpr: number }>({
    scale: 1,
    ox: 0,
    oy: 0,
    w: 1,
    h: 1,
    dpr: 1,
  })

  useEffect(() => {
    if (!open) return
    setTab('crop')
    setWorkingSrc(imageSrc)
    setRefineZoom(1)
    setRefineCenter({ x: 0, y: 0 })
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
        const host = refineHostRef.current
        if (!canvas || !host) return
        const dpr = window.devicePixelRatio || 1
        const hostRect = host.getBoundingClientRect()
        const cw = Math.max(1, Math.round(hostRect.width * dpr))
        const ch = Math.max(1, Math.round(hostRect.height * dpr))
        canvas.width = cw
        canvas.height = ch
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

        // Offscreen buffer at native resolution.
        const off = document.createElement('canvas')
        off.width = w
        off.height = h
        const offCtx = off.getContext('2d')
        if (!offCtx) return
        offCtx.putImageData(workingDataRef.current, 0, 0)
        offscreenRef.current = off

        // Compute contain transform (native -> visible canvas).
        const baseScale = Math.min(cw / w, ch / h)
        const scale = baseScale * refineZoom
        const drawW = w * scale
        const drawH = h * scale
        const centerX = refineCenter.x || w / 2
        const centerY = refineCenter.y || h / 2
        const ox = cw / 2 - centerX * scale
        const oy = ch / 2 - centerY * scale
        viewRef.current = { scale, ox, oy, w, h, dpr }

        // Initial paint
        drawCheckerboard(ctx, cw, ch)
        ctx.drawImage(off, ox, oy, drawW, drawH)
      } finally {
        if (!cancelled) setLoadingRefine(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [open, tab, workingSrc, originalSrc, refineZoom, refineCenter])

  useEffect(() => {
    if (!open || tab !== 'refine') return
    const canvas = canvasRef.current
    const host = refineHostRef.current
    const off = offscreenRef.current
    const data = workingDataRef.current
    if (!canvas || !host || !off || !data) return
    const dpr = window.devicePixelRatio || 1
    const hostRect = host.getBoundingClientRect()
    const cw = Math.max(1, Math.round(hostRect.width * dpr))
    const ch = Math.max(1, Math.round(hostRect.height * dpr))
    const w = off.width
    const h = off.height
    canvas.width = cw
    canvas.height = ch
    const baseScale = Math.min(cw / w, ch / h)
    const scale = baseScale * refineZoom
    const centerX = refineCenter.x || w / 2
    const centerY = refineCenter.y || h / 2
    const ox = cw / 2 - centerX * scale
    const oy = ch / 2 - centerY * scale
    viewRef.current = { scale, ox, oy, w, h, dpr }
    scheduleCanvasRedraw()
  }, [open, tab, refineZoom, refineCenter])

  function scheduleCanvasRedraw() {
    if (rafRef.current != null) return
    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = null
      const canvas = canvasRef.current
      const ctx = canvas?.getContext('2d')
      const data = workingDataRef.current
      const off = offscreenRef.current
      const v = viewRef.current
      if (!canvas || !ctx || !data || !off) return
      const offCtx = off.getContext('2d')
      if (!offCtx) return
      offCtx.putImageData(data, 0, 0)
      drawCheckerboard(ctx, canvas.width, canvas.height)
      ctx.drawImage(off, v.ox, v.oy, v.w * v.scale, v.h * v.scale)
    })
  }

  function paintAt(clientX: number, clientY: number) {
    const canvas = canvasRef.current
    const orig = originalDataRef.current
    const work = workingDataRef.current
    if (!canvas || !orig || !work) return
    const rect = canvas.getBoundingClientRect()
    const v = viewRef.current
    const dpr = v.dpr || (window.devicePixelRatio || 1)
    const cx = (clientX - rect.left) * dpr
    const cy = (clientY - rect.top) * dpr
    const x = Math.round((cx - v.ox) / v.scale)
    const y = Math.round((cy - v.oy) / v.scale)
    const r = Math.max(4, Math.round(brushSize))
    const w = orig.width
    const h = orig.height
    if (x < 0 || y < 0 || x >= w || y >= h) return
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
    const canvas = offscreenRef.current
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
              <div ref={refineHostRef} className="relative h-full w-full">
                <canvas
                  ref={canvasRef}
                  className="h-full w-full touch-none"
                  onWheel={(e) => {
                    // Two-finger trackpad scroll should zoom in/out.
                    e.preventDefault()
                    const canvas = canvasRef.current
                    const off = offscreenRef.current
                    if (!canvas || !off) return
                    const v = viewRef.current
                    const rect = canvas.getBoundingClientRect()
                    const dpr = v.dpr || (window.devicePixelRatio || 1)
                    const cx = (e.clientX - rect.left) * dpr
                    const cy = (e.clientY - rect.top) * dpr
                    // Image coords under cursor before zoom
                    const ix = (cx - v.ox) / v.scale
                    const iy = (cy - v.oy) / v.scale

                    const factor = Math.exp(-e.deltaY * 0.0015)
                    const nextZoom = Math.min(4, Math.max(1, refineZoom * factor))
                    if (!Number.isFinite(nextZoom)) return

                    setRefineZoom(nextZoom)
                    // Keep the same image point under cursor by setting center accordingly.
                    // Center is where canvas center maps to in image coords after zoom.
                    const host = refineHostRef.current
                    if (!host) return
                    const hostRect = host.getBoundingClientRect()
                    const cw = Math.max(1, Math.round(hostRect.width * dpr))
                    const ch = Math.max(1, Math.round(hostRect.height * dpr))
                    const baseScale = Math.min(cw / off.width, ch / off.height)
                    const newScale = baseScale * nextZoom
                    const newCenterX = (ix * newScale - (cx - cw / 2)) / newScale
                    const newCenterY = (iy * newScale - (cy - ch / 2)) / newScale
                    setRefineCenter({
                      x: Math.max(0, Math.min(off.width, newCenterX)),
                      y: Math.max(0, Math.min(off.height, newCenterY)),
                    })
                  }}
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
                  <button
                    type="button"
                    onClick={() => {
                      setRefineZoom(1)
                      setRefineCenter({ x: 0, y: 0 })
                    }}
                    className="mt-3 w-full rounded-full border border-[var(--color-line)] bg-white px-4 py-2 text-sm font-semibold text-[var(--color-ink)] hover:bg-[var(--color-paper)]"
                  >
                    Recenter view
                  </button>
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
              Tip: Use <span className="font-semibold">Restore</span> to bring back parts of the item, and{' '}
              <span className="font-semibold">Erase</span> to remove leftover background. You can switch between them as needed.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}

