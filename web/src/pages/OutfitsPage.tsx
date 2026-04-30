import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { createOutfit, deleteOutfit, fetchItems, fetchOutfits, updateOutfit } from '../api'
import { MultiSelectDropdown } from '../components/MultiSelectDropdown'
import { OutfitCoverEditorModal } from '../components/OutfitCoverEditorModal'
import { closetLabel, CLOSET_CATEGORIES, CLOSET_COLORS, closetColorSwatch, SUBCATEGORIES_BY_CATEGORY } from '../closetCatalog'
import { fileToDataUrl, removeBackgroundToDataUrl } from '../removeBackground'
import type { Item, Outfit, OutfitExtra, OutfitLayoutLayer, OutfitPicture } from '../types'

const WEATHER_TAGS = ['Hot', 'Warm', 'Mild', 'Cold', 'Freezing', 'Rain', 'Snow'] as const
const SEASONS = ['Summer', 'Autumn', 'Winter', 'Spring'] as const
const DEFAULT_COVER_ITEM_SCALE = 1.7

export function OutfitsPage() {
  const [items, setItems] = useState<Item[]>([])
  const [outfits, setOutfits] = useState<Outfit[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [modalOpen, setModalOpen] = useState(false)
  const [mode, setMode] = useState<'create' | 'edit'>('create')
  const [editingId, setEditingId] = useState<number | null>(null)
  const [tab, setTab] = useState<'details' | 'cover' | 'pictures' | 'extra'>('details')
  const [saving, setSaving] = useState(false)

  const [name, setName] = useState('')
  const [wears, setWears] = useState('0')
  const [selectedItemIds, setSelectedItemIds] = useState<number[]>([])
  const [extra, setExtra] = useState<OutfitExtra>({})
  const [coverDataUrl, setCoverDataUrl] = useState<string | null>(null)
  const [layout, setLayout] = useState<OutfitLayoutLayer[]>([])
  const [pictures, setPictures] = useState<OutfitPicture[]>([])
  const [pictureAddBusy, setPictureAddBusy] = useState(false)
  const [removingBgId, setRemovingBgId] = useState<string | null>(null)
  const outfitPhotoInputRef = useRef<HTMLInputElement | null>(null)
  const [coverEditorOpen, setCoverEditorOpen] = useState(false)

  const [itemSearch, setItemSearch] = useState('')
  const [filterOpen, setFilterOpen] = useState(false)
  const [draftFilters, setDraftFilters] = useState<{
    colors: string[]
    categories: string[]
    subcategories: string[]
  }>({ colors: [], categories: [], subcategories: [] })

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

  function resetForm() {
    setName('')
    setWears('0')
    setSelectedItemIds([])
    setExtra({})
    setCoverDataUrl(null)
    setLayout([])
    setPictures([])
    setPictureAddBusy(false)
    setRemovingBgId(null)
    setCoverEditorOpen(false)
    setItemSearch('')
    setDraftFilters({ colors: [], categories: [], subcategories: [] })
    setTab('details')
  }

  function openAddModal() {
    setMode('create')
    setEditingId(null)
    resetForm()
    setModalOpen(true)
  }

  function openEditModal(o: Outfit) {
    setMode('edit')
    setEditingId(o.id)
    setName(o.name ?? '')
    setWears(String(o.wears ?? 0))
    setSelectedItemIds(Array.isArray(o.itemIds) ? o.itemIds : [])
    setExtra((o.extra && typeof o.extra === 'object' ? o.extra : {}) as OutfitExtra)
    setCoverDataUrl(o.coverDataUrl ?? null)
    setLayout(Array.isArray(o.layout) ? (o.layout as OutfitLayoutLayer[]) : [])
    setPictures(
      Array.isArray(o.pictures) ? o.pictures.map((p) => ({ ...p, backgroundRemoved: p.backgroundRemoved === true })) : [],
    )
    setItemSearch('')
    setDraftFilters({ colors: [], categories: [], subcategories: [] })
    setTab('details')
    setModalOpen(true)
  }

  function closeModal() {
    setModalOpen(false)
    resetForm()
  }

  function toggleItem(id: number) {
    setSelectedItemIds((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]))
  }

  const filteredItems = useMemo(() => {
    const q = itemSearch.trim().toLowerCase()
    const colorSet = new Set(draftFilters.colors.map(String))
    const catSet = new Set(draftFilters.categories.map((x) => String(x).toUpperCase()))
    const subSet = new Set(draftFilters.subcategories.map((x) => String(x).toUpperCase()))
    return items.filter((it) => {
      if (q) {
        const hay = `${it.name ?? ''} ${it.category ?? ''} ${it.subcategory ?? ''} #${it.id}`.toLowerCase()
        if (!hay.includes(q)) return false
      }
      if (draftFilters.colors.length) {
        const itColors = new Set((it.colors ?? []).map(String))
        let ok = false
        for (const c of colorSet) if (itColors.has(c)) ok = true
        if (!ok) return false
      }
      if (draftFilters.categories.length) {
        if (!catSet.has(String(it.category ?? '').toUpperCase())) return false
      }
      if (draftFilters.subcategories.length) {
        if (!subSet.has(String(it.subcategory ?? '').toUpperCase())) return false
      }
      return true
    })
  }, [items, itemSearch, draftFilters])

  const picturesSorted = useMemo(() => {
    return [...pictures].sort((a, b) => {
      const ta = new Date(a.takenAt).getTime()
      const tb = new Date(b.takenAt).getTime()
      return (Number.isNaN(tb) ? 0 : tb) - (Number.isNaN(ta) ? 0 : ta)
    })
  }, [pictures])

  const onPickOutfitPhoto = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setPictureAddBusy(true)
    setError(null)
    try {
      const usable = await ensureBrowserReadableImage(file)
      const dataUrl = await fileToDataUrl(usable)
      const lastMod = usable.lastModified && usable.lastModified > 0 ? usable.lastModified : Date.now()
      const takenAt = new Date(lastMod).toISOString()
      const pic: OutfitPicture = {
        id: crypto.randomUUID(),
        dataUrl,
        takenAt,
        backgroundRemoved: false,
      }
      setPictures((prev) => [...prev, pic])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not add photo')
    } finally {
      setPictureAddBusy(false)
    }
  }, [])

  const onRemoveBackgroundForPicture = useCallback(async (pic: OutfitPicture) => {
    setRemovingBgId(pic.id)
    setError(null)
    try {
      const f = await dataUrlToFile(pic.dataUrl, `outfit-${pic.id}.png`)
      const { dataUrl, removed } = await removeBackgroundToDataUrl(f)
      setPictures((prev) =>
        prev.map((p) => (p.id === pic.id ? { ...p, dataUrl, backgroundRemoved: p.backgroundRemoved || removed } : p)),
      )
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Background removal failed')
    } finally {
      setRemovingBgId(null)
    }
  }, [])

  const totalCost = useMemo(() => {
    let sum = 0
    for (const id of selectedItemIds) {
      const it = itemById.get(id)
      if (!it) continue
      const p = Number(it.price) || 0
      sum += p
    }
    return sum
  }, [selectedItemIds, itemById])

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    if (selectedItemIds.length === 0) return
    setSaving(true)
    setError(null)
    try {
      const body = {
        name: name.trim(),
        wears: Math.max(0, parseInt(wears || '0', 10) || 0),
        itemIds: selectedItemIds,
        coverDataUrl,
        extra,
        layout,
        pictures,
      }
      if (mode === 'edit' && editingId != null) {
        await updateOutfit(editingId, body)
      } else {
        await createOutfit(body)
      }
      closeModal()
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save outfit')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <OutfitCoverEditorModal
        open={coverEditorOpen}
        items={items.filter((it) => selectedItemIds.includes(it.id))}
        layers={
          layout.length
            ? layout
            : selectedItemIds.map((id, idx) => ({
                itemId: id,
                x: 0.5,
                y: 0.5,
                scale: DEFAULT_COVER_ITEM_SCALE,
                rotationDeg: 0,
                z: idx,
              }))
        }
        onCancel={() => setCoverEditorOpen(false)}
        onSave={({ coverDataUrl: cd, layers: nextLayers }) => {
          setCoverDataUrl(cd)
          setLayout(nextLayers)
          setCoverEditorOpen(false)
        }}
      />
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-3xl">
          Outfits
        </h1>
      </div>

      {error && (
        <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {error}
        </div>
      )}

      {loading ? <p className="text-sm text-[var(--color-muted)]">Loading…</p> : null}

      <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-4 lg:grid-cols-4">
        <li>
          <button
            type="button"
            onClick={openAddModal}
            className="flex aspect-[3/4] w-full flex-col items-center justify-center rounded-3xl border-2 border-dashed border-[var(--color-sage)]/40 bg-white text-[var(--color-sage)] shadow-sm transition hover:border-[var(--color-sage)] hover:bg-[var(--color-accent-soft)]"
          >
            <span className="text-4xl font-light leading-none">+</span>
            <span className="mt-2 text-xs font-semibold uppercase tracking-wide">Add outfit</span>
          </button>
        </li>
        {outfits.map((o) => (
          <li key={o.id}>
            <div className="group relative flex aspect-[3/4] h-full flex-col overflow-hidden rounded-3xl border border-[var(--color-line)] bg-white p-4 shadow-sm ring-1 ring-transparent transition hover:-translate-y-0.5 hover:shadow-md hover:ring-[var(--color-sage)]/25">
              <button
                type="button"
                onClick={() => openEditModal(o)}
                className="absolute right-3 top-3 inline-flex items-center justify-center rounded-full border border-[var(--color-line)] bg-white/90 p-2 text-[var(--color-muted)] opacity-0 shadow-sm backdrop-blur transition hover:text-[var(--color-ink)] group-hover:opacity-100"
                aria-label={`Edit ${o.name}`}
              >
                <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M12 20h9" />
                  <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4 11.5-11.5z" />
                </svg>
              </button>
              <p className="text-[10px] font-semibold uppercase tracking-wide text-[var(--color-sage)]">#{o.id}</p>
              {o.coverDataUrl ? (
                <div className="mt-2 flex flex-1 items-center justify-center rounded-2xl bg-[var(--color-surface)] p-2">
                  <img src={o.coverDataUrl} alt={o.name} className="block max-h-full max-w-full rounded-xl object-contain object-center" loading="lazy" />
                </div>
              ) : (
                <div className="mt-2 flex flex-1 items-center justify-center rounded-2xl bg-[var(--color-surface)] p-2 text-xs text-[var(--color-muted)]">
                  No cover yet
                </div>
              )}
              <h2 className="mt-1 line-clamp-2 text-sm font-semibold leading-snug text-[var(--color-ink)] sm:text-base">
                {o.name}
              </h2>
              <p className="mt-1 text-xs text-[var(--color-muted)]">{o.wears} wears</p>
              <div className="mt-auto pt-2 text-[10px] text-[var(--color-muted)]">
                Total cost: ${totalCostFor(o, itemById).toFixed(0)}
              </div>
            </div>
          </li>
        ))}
      </ul>

      {modalOpen ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="Edit outfit"
          onClick={closeModal}
        >
          <div
            className="max-h-[90vh] w-full max-w-3xl overflow-y-auto rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-2">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">{mode === 'edit' ? 'Edit outfit' : 'New outfit'}</h2>
              <button type="button" onClick={closeModal} className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]">
                Close
              </button>
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-1 rounded-2xl bg-[var(--color-surface)] p-1 sm:gap-2">
              <button
                type="button"
                onClick={() => setTab('details')}
                className={`min-w-0 flex-1 rounded-xl px-2 py-2 text-sm font-semibold transition sm:px-3 ${
                  tab === 'details' ? 'bg-white text-[var(--color-ink)] shadow-sm' : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
                }`}
              >
                Details
              </button>
              <button
                type="button"
                onClick={() => setTab('cover')}
                className={`min-w-0 flex-1 rounded-xl px-2 py-2 text-sm font-semibold transition sm:px-3 ${
                  tab === 'cover' ? 'bg-white text-[var(--color-ink)] shadow-sm' : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
                }`}
              >
                Cover
              </button>
              <button
                type="button"
                onClick={() => setTab('pictures')}
                className={`min-w-0 flex-1 rounded-xl px-2 py-2 text-sm font-semibold transition sm:px-3 ${
                  tab === 'pictures' ? 'bg-white text-[var(--color-ink)] shadow-sm' : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
                }`}
              >
                Pictures
              </button>
              <button
                type="button"
                onClick={() => setTab('extra')}
                className={`min-w-0 flex-1 rounded-xl px-2 py-2 text-sm font-semibold transition sm:px-3 ${
                  tab === 'extra' ? 'bg-white text-[var(--color-ink)] shadow-sm' : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
                }`}
              >
                Extra info
              </button>
            </div>

            <form className="mt-4 space-y-4" onSubmit={onSubmit}>
              {tab === 'details' ? (
                <>
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Name
                      <input
                        required
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                        placeholder="Sunday brunch"
                      />
                    </label>
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Total wears
                      <input
                        type="number"
                        min={0}
                        value={wears}
                        onChange={(e) => setWears(e.target.value)}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      />
                    </label>
                  </div>

                  <div className="rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">Included items ({selectedItemIds.length})</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {selectedItemIds.length === 0 ? (
                        <span className="text-xs text-[var(--color-muted)]">None yet.</span>
                      ) : (
                        selectedItemIds.map((id) => {
                          const it = itemById.get(id)
                          return (
                            <span
                              key={id}
                              className="inline-flex items-center gap-2 rounded-full bg-[var(--color-surface)] px-3 py-1 text-xs font-medium text-[var(--color-sage-muted)] ring-1 ring-[var(--color-line)]"
                            >
                              {it ? it.name : `Item ${id}`}
                              <button type="button" className="rounded-full px-1.5 py-0.5 hover:bg-white" onClick={() => toggleItem(id)}>
                                ×
                              </button>
                            </span>
                          )
                        })
                      )}
                    </div>
                  </div>

                  <div className="rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                      <label className="block flex-1 text-xs font-medium text-[var(--color-muted)]">
                        Search items
                        <input
                          value={itemSearch}
                          onChange={(e) => setItemSearch(e.target.value)}
                          className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                          placeholder="Search by name, type, or #id"
                        />
                      </label>
                      <button
                        type="button"
                        onClick={() => setFilterOpen(true)}
                        className="rounded-full border border-[var(--color-line)] bg-white px-4 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
                      >
                        Filter
                      </button>
                    </div>

                    <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
                      {filteredItems.map((it) => {
                        const on = selectedItemIds.includes(it.id)
                        return (
                          <button
                            key={it.id}
                            type="button"
                            onClick={() => toggleItem(it.id)}
                            className={`group relative flex aspect-square flex-col overflow-hidden rounded-3xl border p-3 text-left shadow-sm transition ${
                              on ? 'border-[var(--color-sage)] ring-2 ring-[var(--color-sage)]/20' : 'border-[var(--color-line)] hover:shadow-md'
                            }`}
                          >
                            <div className="flex items-center justify-between">
                              <span className="text-[10px] font-semibold uppercase tracking-wide text-[var(--color-sage)]">
                                #{it.id}
                              </span>
                              <span
                                className={`rounded-full px-2 py-1 text-[10px] font-semibold ${
                                  on ? 'bg-[var(--color-sage)] text-white' : 'bg-[var(--color-surface)] text-[var(--color-muted)]'
                                }`}
                              >
                                {on ? 'Added' : 'Add'}
                              </span>
                            </div>
                            {it.photoDataUrl ? (
                              <div className="mt-2 flex flex-1 items-center justify-center rounded-2xl bg-[var(--color-surface)] p-2">
                                <img src={it.photoDataUrl} alt={it.name} className="block max-h-full max-w-full rounded-xl object-contain object-center" loading="lazy" />
                              </div>
                            ) : (
                              <div className="mt-2 flex flex-1 items-center justify-center rounded-2xl bg-[var(--color-surface)] p-2 text-[10px] text-[var(--color-muted)]">
                                No photo
                              </div>
                            )}
                            <div className="mt-2">
                              <div className="line-clamp-2 text-xs font-semibold text-[var(--color-ink)]">{it.name}</div>
                              <div className="mt-0.5 text-[10px] text-[var(--color-muted)]">{closetLabel(it.subcategory)}</div>
                            </div>
                          </button>
                        )
                      })}
                    </div>
                  </div>
                </>
              ) : tab === 'cover' ? (
                <>
                  <div className="rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">Cover</div>
                    <div className="mt-2 rounded-2xl bg-[var(--color-surface)] p-2">
                      {coverDataUrl ? (
                        <img src={coverDataUrl} alt="" className="block h-64 w-full rounded-xl object-contain object-center" />
                      ) : (
                        <div className="flex h-64 items-center justify-center text-xs text-[var(--color-muted)]">
                          Build a cover collage from your selected items.
                        </div>
                      )}
                    </div>
                    <div className="mt-3 flex gap-2">
                      <button
                        type="button"
                        onClick={() => setCoverEditorOpen(true)}
                        disabled={selectedItemIds.length === 0}
                        className="flex-1 rounded-full border border-[var(--color-line)] bg-white px-4 py-2 text-sm font-semibold text-[var(--color-sage)] hover:bg-[var(--color-hover)] disabled:opacity-60"
                      >
                        Edit cover
                      </button>
                      {coverDataUrl ? (
                        <button
                          type="button"
                          onClick={() => {
                            setCoverDataUrl(null)
                            setLayout([])
                          }}
                          className="rounded-full border border-[var(--color-line)] bg-white px-4 py-2 text-sm font-semibold text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
                        >
                          Clear
                        </button>
                      ) : null}
                    </div>
                    <div className="mt-2 text-xs text-[var(--color-muted)]">Total cost: ${totalCost.toFixed(2)}</div>
                  </div>
                </>
              ) : tab === 'pictures' ? (
                <>
                  <input
                    ref={outfitPhotoInputRef}
                    type="file"
                    accept="image/*,.heic,.heif"
                    className="hidden"
                    onChange={onPickOutfitPhoto}
                  />
                  <div className="rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">You in this outfit</div>
                    <div className="mt-3">
                      <button
                        type="button"
                        onClick={() => outfitPhotoInputRef.current?.click()}
                        disabled={pictureAddBusy}
                        className="w-full rounded-full border border-[var(--color-line)] bg-white py-2.5 text-sm font-semibold text-[var(--color-sage)] hover:bg-[var(--color-hover)] disabled:opacity-60 sm:w-auto sm:px-6"
                      >
                        {pictureAddBusy ? 'Adding…' : 'Add picture'}
                      </button>
                    </div>
                    {picturesSorted.length > 0 ? (
                      <ul className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
                        {picturesSorted.map((pic) => (
                          <li
                            key={pic.id}
                            className="overflow-hidden rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)]"
                          >
                            <div
                              className="flex aspect-[3/4] w-full items-center justify-center p-2"
                              style={pic.backgroundRemoved ? { background: 'repeating-conic-gradient(#e8e8e8 0% 25%, #f5f5f5 0% 50%) 50% / 20px 20px' } : undefined}
                            >
                              <img
                                src={pic.dataUrl}
                                alt=""
                                className="max-h-full max-w-full object-contain"
                                loading="lazy"
                              />
                            </div>
                            <div className="space-y-2 border-t border-[var(--color-line)] bg-white/90 px-3 py-2.5">
                              <p className="text-[11px] text-[var(--color-muted)]">{formatOutfitPhotoDate(pic.takenAt)}</p>
                              {pic.backgroundRemoved ? (
                                <p className="text-[10px] font-medium uppercase tracking-wide text-[var(--color-sage)]">Background removed</p>
                              ) : null}
                              <div className="flex flex-wrap gap-2">
                                {pic.backgroundRemoved ? null : (
                                  <button
                                    type="button"
                                    onClick={() => void onRemoveBackgroundForPicture(pic)}
                                    disabled={removingBgId === pic.id || pictureAddBusy}
                                    className="flex-1 rounded-full border border-[var(--color-line)] bg-white px-2 py-1.5 text-xs font-semibold text-[var(--color-ink)] hover:bg-[var(--color-hover)] disabled:opacity-50"
                                  >
                                    {removingBgId === pic.id ? 'Removing…' : 'Remove background'}
                                  </button>
                                )}
                                <button
                                  type="button"
                                  onClick={() => setPictures((p) => p.filter((x) => x.id !== pic.id))}
                                  className={`rounded-full border border-red-200 bg-white px-2 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-50 ${pic.backgroundRemoved ? 'flex-1' : ''}`}
                                >
                                  Remove
                                </button>
                              </div>
                            </div>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="mt-3 text-xs text-[var(--color-muted)]">No pictures yet.</p>
                    )}
                  </div>
                </>
              ) : (
                <>
                  <div className="rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">Weather</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {WEATHER_TAGS.map((t) => {
                        const on = (extra.weather ?? []).includes(t)
                        return (
                          <button
                            key={t}
                            type="button"
                            onClick={() =>
                              setExtra((e) => ({
                                ...e,
                                weather: on ? (e.weather ?? []).filter((x) => x !== t) : [...(e.weather ?? []), t],
                              }))
                            }
                            className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 transition ${
                              on
                                ? 'bg-[var(--color-sage)] text-white ring-[var(--color-sage)]'
                                : 'bg-[var(--color-surface)] text-[var(--color-ink)] ring-[var(--color-line)] hover:bg-[var(--color-hover)]'
                            }`}
                          >
                            {t}
                          </button>
                        )
                      })}
                    </div>
                  </div>

                  <div className="rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">Season</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {SEASONS.map((s) => {
                        const on = (extra.seasons ?? []).includes(s)
                        return (
                          <button
                            key={s}
                            type="button"
                            onClick={() =>
                              setExtra((e) => ({
                                ...e,
                                seasons: on ? (e.seasons ?? []).filter((x) => x !== s) : [...(e.seasons ?? []), s],
                              }))
                            }
                            className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 transition ${
                              on
                                ? 'bg-[var(--color-sage)] text-white ring-[var(--color-sage)]'
                                : 'bg-[var(--color-surface)] text-[var(--color-ink)] ring-[var(--color-line)] hover:bg-[var(--color-hover)]'
                            }`}
                          >
                            {s}
                          </button>
                        )
                      })}
                    </div>
                  </div>

                  <label className="block text-xs font-medium text-[var(--color-muted)]">
                    Notes
                    <textarea
                      value={extra.notes ?? ''}
                      onChange={(e) => setExtra((x) => ({ ...x, notes: e.target.value }))}
                      rows={4}
                      className="mt-1 w-full resize-none rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      placeholder="Anything you want to remember about this outfit."
                    />
                  </label>
                </>
              )}

              <div className="flex gap-2 pt-2">
                {mode === 'edit' && editingId != null ? (
                  <button
                    type="button"
                    disabled={saving}
                    onClick={async () => {
                      if (!confirm('Delete this outfit? This cannot be undone.')) return
                      setSaving(true)
                      setError(null)
                      try {
                        await deleteOutfit(editingId)
                        closeModal()
                        await load()
                      } catch (err) {
                        setError(err instanceof Error ? err.message : 'Could not delete outfit')
                      } finally {
                        setSaving(false)
                      }
                    }}
                    className="flex-1 rounded-full border border-red-200 bg-white py-2.5 text-sm font-semibold text-red-700 hover:bg-red-50 disabled:opacity-60"
                  >
                    Delete
                  </button>
                ) : null}
                <button
                  type="submit"
                  disabled={saving || !name.trim() || selectedItemIds.length === 0}
                  className="flex-1 rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-60"
                >
                  {saving ? 'Saving…' : 'Save'}
                </button>
              </div>
            </form>

            {filterOpen ? (
              <div
                className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center"
                role="dialog"
                aria-modal="true"
                aria-label="Filter items"
                onClick={() => setFilterOpen(false)}
              >
                <div
                  className="w-full max-w-2xl overflow-hidden rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-xl"
                  onClick={(e) => e.stopPropagation()}
                >
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="text-lg font-semibold text-[var(--color-sage)]">Filter items</h3>
                    <button type="button" onClick={() => setFilterOpen(false)} className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]">
                      Close
                    </button>
                  </div>
                  <div className="mt-5 grid gap-5 sm:grid-cols-2">
                    <MultiSelectDropdown
                      label="Colors"
                      options={CLOSET_COLORS.map((c) => ({ id: c.id, label: closetLabel(c.id), swatch: closetColorSwatch(c.id) }))}
                      selected={draftFilters.colors}
                      setSelected={(next) => setDraftFilters((f) => ({ ...f, colors: next }))}
                    />
                    <MultiSelectDropdown
                      label="Type"
                      options={CLOSET_CATEGORIES.map((c) => ({ id: c, label: closetLabel(c) }))}
                      selected={draftFilters.categories}
                      setSelected={(next) => setDraftFilters((f) => ({ ...f, categories: next }))}
                    />
                    <MultiSelectDropdown
                      label="Subtype"
                      options={Object.values(SUBCATEGORIES_BY_CATEGORY)
                        .flat()
                        .map((s) => ({ id: s, label: closetLabel(s) }))}
                      selected={draftFilters.subcategories}
                      setSelected={(next) => setDraftFilters((f) => ({ ...f, subcategories: next }))}
                      placeholder="Any"
                    />
                  </div>
                  <div className="mt-5 flex gap-2">
                    <button
                      type="button"
                      onClick={() => setDraftFilters({ colors: [], categories: [], subcategories: [] })}
                      className="flex-1 rounded-full border border-[var(--color-line)] py-2.5 text-sm font-semibold text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
                    >
                      Clear
                    </button>
                    <button
                      type="button"
                      onClick={() => setFilterOpen(false)}
                      className="flex-1 rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md"
                    >
                      Done
                    </button>
                  </div>
                </div>
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  )
}

function totalCostFor(o: Outfit, itemById: Map<number, Item>) {
  let sum = 0
  for (const id of o.itemIds ?? []) {
    const it = itemById.get(id)
    if (!it) continue
    sum += Number(it.price) || 0
  }
  return sum
}

function formatOutfitPhotoDate(iso: string) {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
}

async function dataUrlToFile(dataUrl: string, name: string): Promise<File> {
  const r = await fetch(dataUrl)
  const blob = await r.blob()
  return new File([blob], name, { type: blob.type || 'image/png' })
}

async function ensureBrowserReadableImage(file: File): Promise<File> {
  const n = file.name || ''
  const lower = n.toLowerCase()
  const isHeic =
    file.type === 'image/heic' || file.type === 'image/heif' || lower.endsWith('.heic') || lower.endsWith('.heif')
  if (!isHeic) return file
  try {
    const mod = await import('heic2any')
    const heic2any = (mod as { default: (opts: { blob: Blob; toType: string; quality?: number }) => Promise<Blob | Blob[]> }).default
    const out = await heic2any({ blob: file, toType: 'image/jpeg', quality: 0.92 })
    const blob = Array.isArray(out) ? out[0] : out
    const nextName = n.replace(/\.(heic|heif)$/i, '') + '.jpg'
    return new File([blob], nextName, { type: 'image/jpeg', lastModified: file.lastModified })
  } catch {
    return file
  }
}
