import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  createAssignment,
  deleteAssignment,
  fetchAssignments,
  fetchOutfits,
  updateOutfit,
} from '../api'
import { ensureBrowserReadableImage } from '../heicConvert'
import { fileToDataUrl } from '../removeBackground'
import type { Assignment, Outfit, OutfitPicture } from '../types'

function pad2(n: number) {
  return String(n).padStart(2, '0')
}

function monthKey(d: Date) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`
}

function localDateStr(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}

function buildMonthGrid(year: number, monthIndex: number) {
  const first = new Date(year, monthIndex, 1)
  const pad = first.getDay()
  const dim = new Date(year, monthIndex + 1, 0).getDate()
  const cells: { dateStr: string; label: number }[] = []
  for (let i = 0; i < pad; i++) {
    cells.push({ dateStr: '', label: 0 })
  }
  for (let day = 1; day <= dim; day++) {
    cells.push({
      dateStr: `${year}-${pad2(monthIndex + 1)}-${pad2(day)}`,
      label: day,
    })
  }
  while (cells.length % 7 !== 0) {
    cells.push({ dateStr: '', label: 0 })
  }
  return cells
}

function readCalendarViewMode(): 'cover' | 'selfie' {
  try {
    const v = window.localStorage.getItem('calendar:view:mode')
    if (v === 'cover' || v === 'selfie') return v
  } catch {
    // ignore
  }
  return 'cover'
}

export function CalendarPage() {
  const [cursor, setCursor] = useState(() => new Date(new Date().getFullYear(), new Date().getMonth(), 1))
  const [outfits, setOutfits] = useState<Outfit[]>([])
  const [assignments, setAssignments] = useState<Assignment[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [pickDate, setPickDate] = useState<string | null>(null)
  const [outfitId, setOutfitId] = useState<number>(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)
  const [viewOpen, setViewOpen] = useState(false)
  const [calendarViewMode, setCalendarViewMode] = useState<'cover' | 'selfie'>(readCalendarViewMode)
  const [dayPhotoPrompt, setDayPhotoPrompt] = useState<{ day: string; outfitId: number } | null>(null)
  const [dayPhotoBusy, setDayPhotoBusy] = useState(false)
  const dayPhotoInputRef = useRef<HTMLInputElement | null>(null)

  const mk = monthKey(cursor)
  const grid = useMemo(
    () => buildMonthGrid(cursor.getFullYear(), cursor.getMonth()),
    [cursor],
  )

  const byDay = useMemo(() => {
    const m = new Map<string, Assignment>()
    for (const a of assignments) m.set(a.day, a)
    return m
  }, [assignments])

  const outfitById = useMemo(() => {
    const m = new Map<number, Outfit>()
    for (const o of outfits) m.set(o.id, o)
    return m
  }, [outfits])

  useEffect(() => {
    try {
      window.localStorage.setItem('calendar:view:mode', calendarViewMode)
    } catch {
      // ignore
    }
  }, [calendarViewMode])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [ot, as] = await Promise.all([
        fetchOutfits(),
        fetchAssignments(mk),
      ])
      setOutfits(ot)
      setAssignments(as)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load calendar')
    } finally {
      setLoading(false)
    }
  }, [mk])

  useEffect(() => {
    void load()
  }, [load])

  useEffect(() => {
    if (outfits.length > 0 && outfitId === 0) {
      setOutfitId(outfits[0].id)
    }
  }, [outfits, outfitId])

  function prevMonth() {
    setCursor((d) => new Date(d.getFullYear(), d.getMonth() - 1, 1))
  }

  function nextMonth() {
    setCursor((d) => new Date(d.getFullYear(), d.getMonth() + 1, 1))
  }

  async function saveAssignment() {
    if (!pickDate || !outfitId) return
    setSaving(true)
    setError(null)
    const saved = { day: pickDate, outfitId }
    try {
      await createAssignment({ outfitId, day: pickDate, notes })
      setPickDate(null)
      setNotes('')
      await load()
      setDayPhotoPrompt(saved)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    } finally {
      setSaving(false)
    }
  }

  async function onRemove(a: Assignment) {
    if (!confirm(`Clear outfit for ${a.day}?`)) return
    try {
      await deleteAssignment(a.id)
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  const onDayPhotoPicked = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0]
      e.target.value = ''
      if (!file || !dayPhotoPrompt) return
      setDayPhotoBusy(true)
      setError(null)
      try {
        const usable = await ensureBrowserReadableImage(file)
        const dataUrl = await fileToDataUrl(usable)
        const o = outfitById.get(dayPhotoPrompt.outfitId)
        if (!o) throw new Error('Outfit not found')
        const newPic: OutfitPicture = {
          id: crypto.randomUUID(),
          dataUrl,
          takenAt: `${dayPhotoPrompt.day}T12:00:00.000Z`,
          backgroundRemoved: false,
          wornOnDay: dayPhotoPrompt.day,
        }
        const nextPictures = mergeWornOnDayPicture(o.pictures, dayPhotoPrompt.day, newPic)
        await updateOutfit(o.id, {
          name: o.name,
          itemIds: o.itemIds,
          wears: o.wears,
          coverDataUrl: o.coverDataUrl ?? null,
          extra: o.extra ?? null,
          layout: o.layout ?? null,
          pictures: nextPictures,
        })
        setDayPhotoPrompt(null)
        await load()
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Could not add photo')
      } finally {
        setDayPhotoBusy(false)
      }
    },
    [dayPhotoPrompt, outfitById, load],
  )

  const title = cursor.toLocaleString(undefined, { month: 'long', year: 'numeric' })

  return (
    <div className="space-y-10">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-3xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-4xl">
            Outfit calendar
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-[var(--color-muted)]">
            Plan what you’re wearing each day by assigning an outfit to a date.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setViewOpen(true)}
            className="rounded-full border border-[var(--color-line)] bg-white px-4 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
          >
            View
          </button>
          <button
            type="button"
            onClick={prevMonth}
            className="rounded-full border border-[var(--color-line)] bg-white px-3 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
          >
            ←
          </button>
          <span className="min-w-[10rem] text-center text-sm font-semibold text-[var(--color-ink)]">
            {title}
          </span>
          <button
            type="button"
            onClick={nextMonth}
            className="rounded-full border border-[var(--color-line)] bg-white px-3 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
          >
            →
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {error}
        </div>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,1.2fr)_minmax(0,0.9fr)]">
        <section className="rounded-3xl border border-[var(--color-line)] bg-white p-4 shadow-sm sm:p-6">
          {loading ? (
            <p className="text-sm text-[var(--color-muted)]">Loading month…</p>
          ) : (
            <>
              <div className="grid grid-cols-7 gap-1 text-center text-[10px] font-semibold uppercase tracking-wide text-[var(--color-muted)] sm:text-xs">
                {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d) => (
                  <div key={d} className="py-2">
                    {d}
                  </div>
                ))}
              </div>
              <div className="mt-1 grid grid-cols-7 gap-1">
                {grid.map((cell, idx) => {
                  if (!cell.dateStr) {
                    return (
                      <div
                        key={`e-${idx}`}
                        className="aspect-[3/4] rounded-2xl bg-[var(--color-surface)]"
                      />
                    )
                  }
                  const a = byDay.get(cell.dateStr)
                  const o = a ? outfitById.get(a.outfitId) : undefined
                  const thumb = a && o ? calendarCellThumb(o, cell.dateStr, calendarViewMode) : null
                  const isToday = cell.dateStr === localDateStr(new Date())
                  return (
                    <button
                      key={cell.dateStr}
                      type="button"
                      onClick={() => {
                        setPickDate(cell.dateStr)
                        if (a) setOutfitId(a.outfitId)
                        else if (outfits[0]) setOutfitId(outfits[0].id)
                        setNotes(a?.notes ?? '')
                      }}
                      aria-label={
                        a ? `${cell.dateStr}, outfit scheduled` : `${cell.dateStr}, no outfit scheduled`
                      }
                      className={[
                        'relative flex aspect-[3/4] w-full overflow-hidden rounded-2xl border text-sm transition',
                        a && !thumb
                          ? 'border-[var(--color-sage)]/40 bg-[var(--color-accent-soft)]'
                          : a && thumb
                            ? 'border-[var(--color-sage)]/40 bg-[var(--color-surface)]'
                            : 'border-transparent bg-[var(--color-surface)] hover:border-[var(--color-line)]',
                        isToday ? 'border-[var(--color-line)] bg-zinc-200' : '',
                      ].join(' ')}
                    >
                      <span
                        className={[
                          'pointer-events-none absolute left-0.5 top-0.5 z-10 inline-flex h-4 min-w-[1rem] items-center justify-center rounded px-0.5 text-[9px] font-semibold tabular-nums leading-none shadow-sm ring-1 ring-black/[0.06] sm:left-1 sm:top-1 sm:h-[1.125rem] sm:text-[10px]',
                          thumb
                            ? 'bg-white/92 text-[var(--color-ink)]'
                            : a
                              ? 'bg-white/88 text-[var(--color-sage)]'
                              : 'bg-white/88 text-[var(--color-ink)]',
                        ].join(' ')}
                        aria-hidden
                      >
                        {cell.label}
                      </span>
                      {thumb ? (
                        <div className="flex h-full w-full min-h-0 items-center justify-center p-0.5 sm:p-1">
                          <img
                            src={thumb}
                            alt=""
                            className="max-h-full max-w-full object-contain object-center"
                            loading="lazy"
                          />
                        </div>
                      ) : null}
                    </button>
                  )
                })}
              </div>
            </>
          )}
        </section>

        <aside className="space-y-6">
          <div className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">This month</h2>
            <ul className="mt-4 space-y-3 text-sm">
              {assignments.length === 0 ? (
                <li className="text-[var(--color-muted)]">No assignments yet. Tap a day on the grid.</li>
              ) : (
                assignments
                  .slice()
                  .sort((a, b) => a.day.localeCompare(b.day))
                  .map((a) => {
                    const o = outfitById.get(a.outfitId)
                    const sideThumb = o ? calendarCellThumb(o, a.day, calendarViewMode) : null
                    return (
                    <li
                      key={a.id}
                      className="flex items-start justify-between gap-2 rounded-2xl bg-[var(--color-surface)] px-3 py-2 ring-1 ring-[var(--color-line)]"
                    >
                      <div className="flex min-w-0 flex-1 items-start gap-2">
                        {sideThumb ? (
                          <div className="flex aspect-[3/4] w-12 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-[var(--color-surface)] p-0.5 ring-1 ring-[var(--color-line)]">
                            <img
                              src={sideThumb}
                              alt=""
                              className="max-h-full max-w-full object-contain object-center"
                              loading="lazy"
                            />
                          </div>
                        ) : null}
                        <div className="min-w-0">
                          <p className="font-semibold text-[var(--color-ink)]">{a.day}</p>
                          {a.notes ? (
                            <p className="mt-1 text-xs text-[var(--color-sage-muted)]">{a.notes}</p>
                          ) : null}
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() => void onRemove(a)}
                        className="shrink-0 rounded-full border border-red-200 bg-white px-3 py-1 text-xs font-semibold text-red-700 hover:bg-red-50"
                      >
                        Clear
                      </button>
                    </li>
                    )
                  })
              )}
            </ul>
          </div>

          {pickDate && (
            <div className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">
                {pickDate}
              </p>
              <h3 className="mt-1 text-lg font-semibold text-[var(--color-sage)]">Assign outfit</h3>
              {outfits.length === 0 ? (
                <p className="mt-2 text-sm text-[var(--color-muted)]">
                  Create outfits first, then return here.
                </p>
              ) : (
                <div className="mt-4 space-y-3">
                  <label className="block text-xs font-medium text-[var(--color-muted)]">
                    Outfit
                    <select
                      value={outfitId}
                      onChange={(e) => setOutfitId(Number(e.target.value))}
                      className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                    >
                      {outfits.map((o) => (
                        <option key={o.id} value={o.id}>
                          {o.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="block text-xs font-medium text-[var(--color-muted)]">
                    Notes (optional)
                    <input
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      placeholder="e.g. dinner reservation"
                    />
                  </label>
                  <div className="flex gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => setPickDate(null)}
                      className="flex-1 rounded-full border border-[var(--color-line)] bg-white py-2 text-sm font-medium text-[var(--color-muted)]"
                    >
                      Cancel
                    </button>
                    <button
                      type="button"
                      disabled={saving}
                      onClick={() => void saveAssignment()}
                      className="flex-1 rounded-full bg-[var(--color-sage)] py-2 text-sm font-semibold text-white shadow-sm ring-1 ring-[var(--color-sage)]/20 disabled:opacity-50"
                    >
                      {saving ? 'Saving…' : 'Save'}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </aside>
      </div>

      {viewOpen ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="View options"
          onClick={() => setViewOpen(false)}
        >
          <div
            className="w-full max-w-md overflow-hidden rounded-3xl border border-[var(--color-line)] bg-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-[var(--color-line)] px-5 py-4">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">View</h2>
              <button
                type="button"
                onClick={() => setViewOpen(false)}
                className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
              >
                Close
              </button>
            </div>
            <div className="space-y-3 p-5">
              <p className="text-xs text-[var(--color-muted)]">What to show on each day (when you have an outfit scheduled).</p>
              <div className="grid gap-2 sm:grid-cols-2">
                <button
                  type="button"
                  onClick={() => {
                    setCalendarViewMode('cover')
                    setViewOpen(false)
                  }}
                  className={`rounded-2xl border px-3 py-3 text-left text-sm font-semibold transition ${
                    calendarViewMode === 'cover'
                      ? 'border-[var(--color-sage)] bg-[var(--color-accent-soft)] text-[var(--color-ink)]'
                      : 'border-[var(--color-line)] text-[var(--color-muted)] hover:border-[var(--color-sage)]/40'
                  }`}
                >
                  <span className="block">Outfit covers</span>
                  <span className="mt-0.5 block text-xs font-normal text-[var(--color-muted)]">Collage from the Outfits page</span>
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setCalendarViewMode('selfie')
                    setViewOpen(false)
                  }}
                  className={`rounded-2xl border px-3 py-3 text-left text-sm font-semibold transition ${
                    calendarViewMode === 'selfie'
                      ? 'border-[var(--color-sage)] bg-[var(--color-accent-soft)] text-[var(--color-ink)]'
                      : 'border-[var(--color-line)] text-[var(--color-muted)] hover:border-[var(--color-sage)]/40'
                  }`}
                >
                  <span className="block">Worn photos</span>
                  <span className="mt-0.5 block text-xs font-normal text-[var(--color-muted)]">Your outfit selfies for that day</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {dayPhotoPrompt ? (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="Add photo for this outfit day"
          onClick={() => {
            if (!dayPhotoBusy) setDayPhotoPrompt(null)
          }}
        >
          <div
            className="w-full max-w-md rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <input
              ref={dayPhotoInputRef}
              type="file"
              accept="image/*,image/heic,image/heif,.heic,.heif"
              className="hidden"
              onChange={onDayPhotoPicked}
            />
            <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">
              {dayPhotoPrompt.day}
            </p>
            <h2 className="mt-1 text-lg font-semibold text-[var(--color-sage)]">Add a photo for this day?</h2>
            <p className="mt-1 text-sm text-[var(--color-muted)]">
              Your photo is saved to this outfit’s Pictures tab and shown here in Worn photos view.
            </p>
            <div className="mt-5 flex flex-col gap-2 sm:flex-row sm:justify-end">
              <button
                type="button"
                disabled={dayPhotoBusy}
                onClick={() => setDayPhotoPrompt(null)}
                className="rounded-full border border-[var(--color-line)] bg-white py-2.5 text-sm font-medium text-[var(--color-muted)] sm:px-4"
              >
                Skip
              </button>
              <button
                type="button"
                disabled={dayPhotoBusy}
                onClick={() => dayPhotoInputRef.current?.click()}
                className="rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-sm ring-1 ring-[var(--color-sage)]/20 disabled:opacity-50 sm:px-5"
              >
                {dayPhotoBusy ? 'Saving…' : 'Add photo'}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}

function mergeWornOnDayPicture(prev: Outfit['pictures'], day: string, pic: OutfitPicture): OutfitPicture[] {
  const list = (prev ?? []).filter((p) => p.wornOnDay !== day)
  return [...list, pic]
}

function calendarCellThumb(outfit: Outfit, dayStr: string, mode: 'cover' | 'selfie'): string | null {
  if (mode === 'cover') return outfit.coverDataUrl ?? null
  const pics = outfit.pictures ?? []
  const forDay = pics.find((p) => p.wornOnDay === dayStr)
  if (forDay) return forDay.dataUrl
  const sameDate = pics.filter((p) => p.takenAt.length >= 10 && p.takenAt.slice(0, 10) === dayStr)
  if (sameDate.length) {
    return sameDate.sort((a, b) => b.takenAt.localeCompare(a.takenAt))[0]!.dataUrl
  }
  if (pics.length) {
    const sorted = [...pics].sort((a, b) => new Date(b.takenAt).getTime() - new Date(a.takenAt).getTime())
    return sorted[0]!.dataUrl
  }
  return null
}

