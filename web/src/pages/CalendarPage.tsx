import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  createAssignment,
  deleteAssignment,
  fetchAssignments,
  fetchOutfits,
} from '../api'
import type { Assignment, Outfit } from '../types'

function pad2(n: number) {
  return String(n).padStart(2, '0')
}

function monthKey(d: Date) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`
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

  const outfitName = useMemo(() => {
    const m = new Map<number, string>()
    for (const o of outfits) m.set(o.id, o.name)
    return m
  }, [outfits])

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
    try {
      await createAssignment({ outfitId, day: pickDate, notes })
      setPickDate(null)
      setNotes('')
      await load()
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

  const title = cursor.toLocaleString(undefined, { month: 'long', year: 'numeric' })

  return (
    <div className="space-y-10">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1
            className="text-3xl tracking-tight sm:text-4xl"
            style={{ fontFamily: 'Instrument Serif, Georgia, serif' }}
          >
            Outfit calendar
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-[var(--color-muted)]">
            Plan what you’re wearing each day by assigning an outfit to a date.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={prevMonth}
            className="rounded-full border border-[var(--color-line)] bg-white px-3 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-paper)]"
          >
            ←
          </button>
          <span className="min-w-[10rem] text-center text-sm font-semibold text-[var(--color-ink)]">
            {title}
          </span>
          <button
            type="button"
            onClick={nextMonth}
            className="rounded-full border border-[var(--color-line)] bg-white px-3 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-paper)]"
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
        <section className="rounded-3xl border border-[var(--color-line)] bg-white/80 p-4 shadow-sm sm:p-6">
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
                        className="aspect-square rounded-2xl bg-[var(--color-paper)]/40"
                      />
                    )
                  }
                  const a = byDay.get(cell.dateStr)
                  const isToday = cell.dateStr === new Date().toISOString().slice(0, 10)
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
                      className={[
                        'flex aspect-square flex-col items-center justify-center rounded-2xl border text-sm transition',
                        a
                          ? 'border-[var(--color-sage)]/40 bg-[#eef4f1] font-semibold text-[var(--color-sage)]'
                          : 'border-transparent bg-[var(--color-paper)]/60 text-[var(--color-ink)] hover:border-[var(--color-line)]',
                        isToday ? 'ring-2 ring-[var(--color-clay)]/50' : '',
                      ].join(' ')}
                    >
                      <span>{cell.label}</span>
                      {a && (
                        <span className="mt-1 line-clamp-2 px-1 text-[9px] font-normal leading-tight text-[var(--color-muted)] sm:text-[10px]">
                          {outfitName.get(a.outfitId) ?? `Outfit ${a.outfitId}`}
                        </span>
                      )}
                    </button>
                  )
                })}
              </div>
            </>
          )}
        </section>

        <aside className="space-y-6">
          <div className="rounded-3xl border border-[var(--color-line)] bg-white/85 p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">This month</h2>
            <ul className="mt-4 space-y-3 text-sm">
              {assignments.length === 0 ? (
                <li className="text-[var(--color-muted)]">No assignments yet. Tap a day on the grid.</li>
              ) : (
                assignments
                  .slice()
                  .sort((a, b) => a.day.localeCompare(b.day))
                  .map((a) => (
                    <li
                      key={a.id}
                      className="flex items-start justify-between gap-2 rounded-2xl bg-[var(--color-paper)]/80 px-3 py-2 ring-1 ring-[var(--color-line)]"
                    >
                      <div>
                        <p className="font-semibold text-[var(--color-ink)]">{a.day}</p>
                        <p className="text-xs text-[var(--color-muted)]">
                          {outfitName.get(a.outfitId) ?? `Outfit #${a.outfitId}`}
                        </p>
                        {a.notes ? (
                          <p className="mt-1 text-xs text-[var(--color-sage-muted)]">{a.notes}</p>
                        ) : null}
                      </div>
                      <button
                        type="button"
                        onClick={() => void onRemove(a)}
                        className="shrink-0 text-xs font-medium text-red-600 hover:underline"
                      >
                        Clear
                      </button>
                    </li>
                  ))
              )}
            </ul>
          </div>

          {pickDate && (
            <div className="rounded-3xl border border-[var(--color-clay)]/30 bg-[var(--color-clay-soft)]/40 p-6 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-clay)]">
                {pickDate}
              </p>
              <h3 className="mt-1 text-lg font-semibold text-[var(--color-ink)]">Assign outfit</h3>
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
                      className="flex-1 rounded-full bg-[var(--color-clay)] py-2 text-sm font-semibold text-white shadow disabled:opacity-50"
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
    </div>
  )
}
