import { useEffect, useMemo, useRef, useState } from 'react'
import type { Item, OutfitLayoutLayer } from '../types'

type Props = {
  open: boolean
  items: Item[]
  layers: OutfitLayoutLayer[]
  onCancel: () => void
  onSave: (next: { coverDataUrl: string; layers: OutfitLayoutLayer[] }) => void
}

function clamp(n: number, a: number, b: number) {
  return Math.max(a, Math.min(b, n))
}

async function loadImage(src: string): Promise<HTMLImageElement> {
  return await new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('Failed to load image'))
    img.src = src
  })
}

function sortByZ(layers: OutfitLayoutLayer[]) {
  return [...layers].sort((a, b) => (a.z ?? 0) - (b.z ?? 0))
}

const DEFAULT_LAYER_SCALE = 0.8
// Keep preview and export in lockstep so "what you see is what gets saved".
const COVER_ITEM_BASE_RATIO = 0.52

export function OutfitCoverEditorModal({ open, items, layers, onCancel, onSave }: Props) {
  const hostRef = useRef<HTMLDivElement | null>(null)
  const [working, setWorking] = useState<OutfitLayoutLayer[]>([])
  const [selectedItemId, setSelectedItemId] = useState<number | null>(null)
  const [drag, setDrag] = useState<null | { itemId: number; dx: number; dy: number; pointerId: number }>(null)
  const [hostSize, setHostSize] = useState({ width: 0, height: 0 })

  const itemById = useMemo(() => new Map(items.map((it) => [it.id, it])), [items])

  useEffect(() => {
    if (!open) return
    const sorted = sortByZ(layers)
    setWorking(sorted)
    setSelectedItemId(sorted.length ? sorted[sorted.length - 1].itemId : null)
    setDrag(null)
  }, [open, layers])

  const selected = useMemo(() => working.find((l) => l.itemId === selectedItemId) ?? null, [working, selectedItemId])

  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    const update = () => {
      const rect = host.getBoundingClientRect()
      setHostSize({ width: rect.width, height: rect.height })
    }
    update()
    const ro = new ResizeObserver(update)
    ro.observe(host)
    return () => ro.disconnect()
  }, [open])

  function updateLayer(itemId: number, patch: Partial<OutfitLayoutLayer>) {
    setWorking((w) =>
      w.map((l) =>
        l.itemId === itemId
          ? {
              ...l,
              ...patch,
              scale: patch.scale ?? l.scale ?? DEFAULT_LAYER_SCALE,
              rotationDeg: patch.rotationDeg ?? l.rotationDeg ?? 0,
            }
          : l,
      ),
    )
  }

  function bring(itemId: number, dir: 'forward' | 'backward') {
    setWorking((w) => {
      const sorted = sortByZ(w)
      const idx = sorted.findIndex((l) => l.itemId === itemId)
      if (idx < 0) return w
      const swapWith = dir === 'forward' ? idx + 1 : idx - 1
      if (swapWith < 0 || swapWith >= sorted.length) return w
      const a = sorted[idx]
      const b = sorted[swapWith]
      const next = sorted.map((l) => {
        if (l.itemId === a.itemId) return { ...l, z: b.z }
        if (l.itemId === b.itemId) return { ...l, z: a.z }
        return l
      })
      return next
    })
  }

  async function exportCover() {
    const host = hostRef.current
    if (!host) return
    const rect = host.getBoundingClientRect()
    const w = Math.max(320, Math.min(1200, Math.round(rect.width)))
    const h = Math.round(w * (4 / 3))
    const canvas = document.createElement('canvas')
    canvas.width = w
    canvas.height = h
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    // Keep cover background transparent so card/theme background shows through.
    ctx.clearRect(0, 0, w, h)

    const sorted = sortByZ(working)
    const images: Record<number, HTMLImageElement> = {}
    for (const l of sorted) {
      const it = itemById.get(l.itemId)
      if (!it?.photoDataUrl) continue
      if (!images[l.itemId]) images[l.itemId] = await loadImage(it.photoDataUrl)
    }

    for (const l of sorted) {
      const img = images[l.itemId]
      if (!img) continue
      // Allow items to go partially off-canvas in the export.
      const x = (l.x ?? 0.5) * w
      const y = (l.y ?? 0.5) * h
      const s = clamp(l.scale ?? DEFAULT_LAYER_SCALE, 0.2, 4)
      const r = ((l.rotationDeg ?? 0) * Math.PI) / 180

      // Base visual size for each item in the cover.
      // Scale slider applies on top of this.
      const base = Math.min(w, h) * COVER_ITEM_BASE_RATIO
      const iw = img.naturalWidth || img.width
      const ih = img.naturalHeight || img.height
      const fit = base / Math.max(iw, ih)
      const dw = iw * fit * s
      const dh = ih * fit * s

      ctx.save()
      ctx.translate(x, y)
      ctx.rotate(r)
      ctx.drawImage(img, -dw / 2, -dh / 2, dw, dh)
      ctx.restore()
    }

    const dataUrl = canvas.toDataURL('image/png')
    onSave({ coverDataUrl: dataUrl, layers: working })
  }

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center" role="dialog" aria-modal="true">
      <div className="w-full max-w-4xl overflow-visible rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] shadow-xl">
        <div className="flex items-center justify-between border-b border-[var(--color-line)] px-5 py-4">
          <h3 className="text-sm font-semibold text-[var(--color-ink)]">Build cover</h3>
          <button type="button" onClick={onCancel} className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]">
            Close
          </button>
        </div>

        <div className="relative grid gap-4 p-5 sm:grid-cols-[minmax(0,1fr)_280px]">
          <div className="relative z-10">
            <div
              ref={hostRef}
              className="relative aspect-[3/4] touch-none overflow-visible rounded-3xl bg-[var(--color-surface)] ring-1 ring-[var(--color-line)]"
              // TODO(outfit-cover): Fix boundary/clipping model so items can go off-frame and be cropped
              // at the frame edge without any perceived "resizing" on left/right while dragging.
              onPointerMove={(e) => {
                if (!drag) return
                const host = hostRef.current
                if (!host) return
                const rect = host.getBoundingClientRect()
                const px = e.clientX - rect.left - drag.dx
                const py = e.clientY - rect.top - drag.dy
                updateLayer(drag.itemId, {
                  x: px / rect.width,
                  y: py / rect.height,
                })
              }}
              onPointerUp={() => setDrag(null)}
              onPointerCancel={() => setDrag(null)}
              onPointerLeave={() => setDrag(null)}
            >
              {sortByZ(working).map((l) => {
                const it = itemById.get(l.itemId)
                if (!it?.photoDataUrl) return null
                const xPct = (l.x ?? 0.5) * 100
                const yPct = (l.y ?? 0.5) * 100
                const s = clamp(l.scale ?? DEFAULT_LAYER_SCALE, 0.2, 5)
                const r = l.rotationDeg ?? 0
                const on = l.itemId === selectedItemId
                const base = Math.min(hostSize.width || 0, hostSize.height || 0) * COVER_ITEM_BASE_RATIO
                const maxDim = Math.max(24, base * s)
                return (
                  <button
                    key={l.itemId}
                    type="button"
                    className={`absolute z-20 rounded-2xl p-1 transition ${
                      on ? 'ring-2 ring-[var(--color-sage)] bg-[var(--color-paper)]/80' : 'bg-[var(--color-paper)]/40 hover:bg-[var(--color-paper)]/60'
                    }`}
                    style={{
                      left: `${xPct}%`,
                      top: `${yPct}%`,
                      width: `${maxDim}px`,
                      height: `${maxDim}px`,
                      transform: `translate(-50%, -50%) rotate(${r}deg)`,
                      transformOrigin: 'center',
                      willChange: 'transform',
                    }}
                    onPointerDown={(e) => {
                      e.preventDefault()
                      setSelectedItemId(l.itemId)
                      ;(e.currentTarget as HTMLButtonElement).setPointerCapture(e.pointerId)
                      const host = hostRef.current
                      if (!host) return
                      const rect = host.getBoundingClientRect()
                      const px = (l.x ?? 0.5) * rect.width
                      const py = (l.y ?? 0.5) * rect.height
                      setDrag({
                        itemId: l.itemId,
                        dx: e.clientX - rect.left - px,
                        dy: e.clientY - rect.top - py,
                        pointerId: e.pointerId,
                      })
                    }}
                  >
                    <img
                      src={it.photoDataUrl}
                      alt={it.name}
                      className="block h-full w-full object-contain object-center pointer-events-none"
                    />
                  </button>
                )
              })}
            </div>
            <p className="mt-2 text-xs text-[var(--color-muted)]">Drag items to position them. Use controls to resize, rotate, and reorder.</p>
          </div>

          <div className="relative z-0 space-y-4">
            <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-paper)] p-4">
              <div className="text-xs font-semibold text-[var(--color-muted)]">Selected</div>
              <div className="mt-1 text-sm font-semibold text-[var(--color-ink)]">
                {selected ? itemById.get(selected.itemId)?.name ?? `Item ${selected.itemId}` : 'None'}
              </div>

              <label className="mt-4 block text-xs font-medium text-[var(--color-muted)]">
                Size
                <input
                  type="range"
                  min={0}
                  max={1.6}
                  step={0.01}
                  value={selected?.scale ?? DEFAULT_LAYER_SCALE}
                  onChange={(e) => selected && updateLayer(selected.itemId, { scale: Number(e.target.value) })}
                  className="mt-2 w-full"
                  disabled={!selected}
                />
              </label>

              <label className="mt-4 block text-xs font-medium text-[var(--color-muted)]">
                Rotate
                <input
                  type="range"
                  min={-180}
                  max={180}
                  step={1}
                  value={selected?.rotationDeg ?? 0}
                  onChange={(e) => selected && updateLayer(selected.itemId, { rotationDeg: Number(e.target.value) })}
                  className="mt-2 w-full"
                  disabled={!selected}
                />
              </label>

              <button
                type="button"
                onClick={() => selected && updateLayer(selected.itemId, { scale: DEFAULT_LAYER_SCALE, rotationDeg: 0 })}
                className="mt-4 w-full rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] px-4 py-2 text-sm font-semibold text-[var(--color-ink)] hover:bg-[var(--color-hover)] disabled:opacity-60"
                disabled={!selected}
              >
                Reset size & rotation
              </button>

              <div className="mt-4 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => selected && bring(selected.itemId, 'backward')}
                  className="rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] px-4 py-2 text-sm font-semibold text-[var(--color-ink)] hover:bg-[var(--color-hover)] disabled:opacity-60"
                  disabled={!selected}
                >
                  Send back
                </button>
                <button
                  type="button"
                  onClick={() => selected && bring(selected.itemId, 'forward')}
                  className="rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] px-4 py-2 text-sm font-semibold text-[var(--color-ink)] hover:bg-[var(--color-hover)] disabled:opacity-60"
                  disabled={!selected}
                >
                  Bring forward
                </button>
              </div>
            </div>

            <div className="flex gap-2">
              <button type="button" onClick={onCancel} className="flex-1 rounded-full border border-[var(--color-line)] py-2.5 text-sm font-semibold text-[var(--color-muted)] hover:bg-[var(--color-hover)]">
                Cancel
              </button>
              <button type="button" onClick={() => void exportCover()} className="flex-1 rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md">
                Save cover
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

