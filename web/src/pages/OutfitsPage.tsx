import { useCallback, useEffect, useMemo, useState } from 'react'
import { createOutfit, fetchItems, fetchOutfits } from '../api'
import type { Item, Outfit } from '../types'

export function OutfitsPage() {
  const [items, setItems] = useState<Item[]>([])
  const [outfits, setOutfits] = useState<Outfit[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [selected, setSelected] = useState<number[]>([])
  const [saving, setSaving] = useState(false)

  const itemById = useMemo(() => {
    const m = new Map<number, Item>()
    for (const it of items) m.set(it.id, it)
    return m
  }, [items])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [it, ot] = await Promise.all([fetchItems(), fetchOutfits()])
      setItems(it)
      setOutfits(ot)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  function toggle(id: number) {
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]))
  }

  async function onCreate(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    setError(null)
    try {
      await createOutfit({ name: name.trim(), itemIds: selected })
      setName('')
      setSelected([])
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create outfit')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-10">
      <div>
        <h1
          className="text-3xl tracking-tight sm:text-4xl"
          style={{ fontFamily: 'Instrument Serif, Georgia, serif' }}
        >
          Outfits
        </h1>
        <p className="mt-1 max-w-2xl text-sm text-[var(--color-muted)]">
          Create looks by combining items from your closet, then save them for later.
        </p>
      </div>

      {error && (
        <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {error}
        </div>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_360px]">
        <section>
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-[var(--color-muted)]">
              Saved looks
            </h2>
            <button
              type="button"
              onClick={() => void load()}
              className="text-sm font-medium text-[var(--color-sage)] hover:underline"
            >
              Refresh
            </button>
          </div>
          {loading ? (
            <p className="text-sm text-[var(--color-muted)]">Loading…</p>
          ) : outfits.length === 0 ? (
            <div className="rounded-3xl border border-dashed border-[var(--color-line)] bg-white/50 p-10 text-center text-sm text-[var(--color-muted)]">
              No outfits yet. Pick items and name your first look.
            </div>
          ) : (
            <ul className="space-y-4">
              {outfits.map((o) => (
                <li
                  key={o.id}
                  className="rounded-3xl border border-[var(--color-line)] bg-white/75 p-5 shadow-sm"
                >
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <h3 className="text-xl font-semibold" style={{ fontFamily: 'Instrument Serif, Georgia, serif' }}>
                      {o.name}
                    </h3>
                    <span className="text-xs text-[var(--color-muted)]">Outfit #{o.id}</span>
                  </div>
                  <p className="mt-1 text-xs text-[var(--color-muted)]">{o.wears} planned wears</p>
                  <ul className="mt-3 flex flex-wrap gap-2">
                    {o.itemIds.map((id) => {
                      const it = itemById.get(id)
                      return (
                        <li
                          key={id}
                          className="rounded-full bg-[var(--color-paper)] px-3 py-1 text-xs font-medium text-[var(--color-sage-muted)] ring-1 ring-[var(--color-line)]"
                        >
                          {it ? it.name : `Item ${id}`}
                        </li>
                      )
                    })}
                  </ul>
                </li>
              ))}
            </ul>
          )}
        </section>

        <aside className="h-fit rounded-3xl border border-[var(--color-line)] bg-white/85 p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-[var(--color-sage)]">Build an outfit</h2>
          <form className="mt-4 space-y-4" onSubmit={onCreate}>
            <label className="block text-xs font-medium text-[var(--color-muted)]">
              Outfit name
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                placeholder="Sunday brunch"
              />
            </label>
            <div>
              <p className="text-xs font-medium text-[var(--color-muted)]">Include items</p>
              <div className="mt-2 max-h-64 space-y-2 overflow-y-auto rounded-2xl border border-[var(--color-line)] bg-[var(--color-paper)]/50 p-2">
                {items.length === 0 ? (
                  <p className="p-2 text-xs text-[var(--color-muted)]">Add items on the Closet page first.</p>
                ) : (
                  items.map((it) => (
                    <label
                      key={it.id}
                      className="flex cursor-pointer items-center gap-3 rounded-xl px-2 py-2 text-sm hover:bg-white/80"
                    >
                      <input
                        type="checkbox"
                        checked={selected.includes(it.id)}
                        onChange={() => toggle(it.id)}
                        className="size-4 rounded border-[var(--color-line)] text-[var(--color-sage)]"
                      />
                      <span className="flex-1 font-medium text-[var(--color-ink)]">{it.name}</span>
                      <span className="text-xs text-[var(--color-muted)]">#{it.id}</span>
                    </label>
                  ))
                )}
              </div>
            </div>
            <button
              type="submit"
              disabled={saving || !name.trim() || selected.length === 0}
              className="w-full rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md transition hover:brightness-95 disabled:opacity-50"
            >
              {saving ? 'Saving…' : 'Save outfit'}
            </button>
          </form>
        </aside>
      </div>
    </div>
  )
}
