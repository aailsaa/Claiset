import { useCallback, useEffect, useMemo, useState } from 'react'
import { createItem, deleteItem, fetchItems, updateItem } from '../api'
import { ClosetColorAddSelect } from '../components/ClosetColorAddSelect'
import { MultiSelectDropdown } from '../components/MultiSelectDropdown'
import { PhotoEditorModal } from '../components/PhotoEditorModal'
import {
  CLOSET_COLORS,
  CLOSET_CATEGORIES,
  closetLabel,
  closetColorSwatch,
  SUBCATEGORIES_BY_CATEGORY,
  type ClosetCategoryId,
} from '../closetCatalog'
import { ensureBrowserReadableImage } from '../heicConvert'
import { fileToDataUrl, removeBackgroundToDataUrl, type BgModel, type BgPostprocessTuning } from '../removeBackground'
import type { Item } from '../types'

function defaultForm() {
  return {
    name: '',
    selectedColors: [] as string[],
    category: 'TOP' as ClosetCategoryId,
    subcategory: 'BLOUSE',
    priceCents: '0',
    wears: '0',
    photoDataUrl: null as string | null,
    purchasedDate: '' as string, // YYYY-MM-DD
    acquisitionMethod: '' as string,
    secondHand: false,
    weather: [] as string[],
    seasons: [] as string[],
    size: '' as string,
    brand: '' as string,
    condition: '' as string,
    locationPurchased: '' as string,
    notes: '' as string,
    archived: false,
    createdAt: null as string | null,
  }
}

function formatCents(digits: string): string {
  const n = parseInt((digits || '0').replace(/\D/g, ''), 10) || 0
  const dollars = Math.floor(n / 100)
  const cents = String(n % 100).padStart(2, '0')
  return `${dollars.toLocaleString()}.${cents}`
}

function dateToRfc3339(dateStr: string): string | null {
  const s = (dateStr || '').trim()
  if (!s) return null
  // Date input gives YYYY-MM-DD; encode as midnight UTC.
  return `${s}T00:00:00Z`
}

function formatAddedToCloset(iso: string) {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
}

const ACQUISITION_METHODS = ['Bought', 'Gifted', 'Handmade', 'Second-hand', 'Traded', 'Rented', 'Other'] as const
const WEATHER_TAGS = ['Hot', 'Warm', 'Mild', 'Cold', 'Freezing', 'Rain', 'Snow'] as const
const SEASONS = ['Summer', 'Autumn', 'Winter', 'Spring'] as const
const CONDITIONS = ['New', 'Like new', 'Good', 'Fair', 'Needs repair'] as const

type ItemFilters = {
  colors: string[]
  categories: string[]
  subcategories: string[]
  acquisitionMethods: string[]
  conditions: string[]
  weather: string[]
  seasons: string[]
  secondHand: 'any' | 'yes' | 'no'
}

const EMPTY_FILTERS: ItemFilters = {
  colors: [],
  categories: [],
  subcategories: [],
  acquisitionMethods: [],
  conditions: [],
  weather: [],
  seasons: [],
  secondHand: 'any',
}

type SortKey =
  | 'recentlyAdded'
  | 'datePurchased'
  | 'price'
  | 'wears'
  | 'itemType'
  | 'color'
  | 'costPerWear'

type NametagKey = 'name' | 'price' | 'costPerWear' | 'wears' | 'brand' | 'datePurchased' | 'itemNumber'

function parseItemDate(itemDate?: string | null): number {
  if (!itemDate) return 0
  const t = Date.parse(itemDate)
  return Number.isFinite(t) ? t : 0
}

function costPerWear(price: number, wears: number): number | null {
  if (!Number.isFinite(price) || !Number.isFinite(wears) || wears <= 0) return null
  return price / wears
}

export function ClosetPage() {
  const [items, setItems] = useState<Item[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState(defaultForm)
  const [saving, setSaving] = useState(false)
  const [modalOpen, setModalOpen] = useState(false)
  const [mode, setMode] = useState<'create' | 'edit'>('create')
  const [editingId, setEditingId] = useState<number | null>(null)
  const [removingBg, setRemovingBg] = useState(false)
  const [photoMessage, setPhotoMessage] = useState<string | null>(null)
  const [tab, setTab] = useState<'details' | 'extra'>('details')
  const [photoEditOpen, setPhotoEditOpen] = useState(false)
  const [photoEditSrc, setPhotoEditSrc] = useState<string | null>(null)
  const [photoEditOriginalSrc, setPhotoEditOriginalSrc] = useState<string | null>(null)
  const [photoOriginalFile, setPhotoOriginalFile] = useState<File | null>(null)
  const [bgModelUsed, setBgModelUsed] = useState<BgModel>('isnet')
  const [bgTuning, setBgTuning] = useState<BgPostprocessTuning>('balanced')
  const [viewOpen, setViewOpen] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [sortOpen, setSortOpen] = useState(false)
  const [appliedFilters, setAppliedFilters] = useState<ItemFilters>(EMPTY_FILTERS)
  const [draftFilters, setDraftFilters] = useState<ItemFilters>(EMPTY_FILTERS)
  const [sortKey, setSortKey] = useState<SortKey>('datePurchased')
  const [sortReversed, setSortReversed] = useState(false)
  const [itemsPerRow, setItemsPerRow] = useState<number>(() => {
    try {
      if (typeof window === 'undefined') return 4
      const raw = window.localStorage.getItem('closet:view:itemsPerRow')
      const n = raw ? Number(raw) : 4
      return Number.isFinite(n) ? Math.min(6, Math.max(2, Math.round(n))) : 4
    } catch {
      return 4
    }
  })
  const [nametagKey, setNametagKey] = useState<NametagKey>(() => {
    try {
      if (typeof window === 'undefined') return 'itemNumber'
      const raw = window.localStorage.getItem('closet:view:nametagKey') as NametagKey | null
      const allowed: NametagKey[] = ['name', 'price', 'costPerWear', 'wears', 'brand', 'datePurchased', 'itemNumber']
      return raw && allowed.includes(raw) ? raw : 'itemNumber'
    } catch {
      return 'itemNumber'
    }
  })

  useEffect(() => {
    try {
      window.localStorage.setItem('closet:view:itemsPerRow', String(itemsPerRow))
    } catch {
      // ignore
    }
  }, [itemsPerRow])

  useEffect(() => {
    try {
      window.localStorage.setItem('closet:view:nametagKey', nametagKey)
    } catch {
      // ignore
    }
  }, [nametagKey])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      setItems(await fetchItems())
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load items')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const sortedItems = useMemo(() => {
    return [...items].sort((a, b) => b.id - a.id)
  }, [items])

  const nametagText = useCallback(
    (it: Item): string => {
      const extra = (it.extra && typeof it.extra === 'object' ? it.extra : {}) as NonNullable<Item['extra']>
      switch (nametagKey) {
        case 'name':
          return it.name?.trim() ? String(it.name) : `Item #${it.id}`
        case 'price': {
          const p = Number(it.price)
          return Number.isFinite(p) ? `$${p.toFixed(0)}` : '—'
        }
        case 'costPerWear': {
          const cpw = costPerWear(Number(it.price) || 0, Number(it.wears) || 0)
          return cpw == null ? '—' : `$${cpw.toFixed(2)}`
        }
        case 'wears':
          return `${Number(it.wears) || 0} wears`
        case 'brand': {
          const b = String((extra as any).brand ?? '').trim()
          return b || '—'
        }
        case 'datePurchased': {
          const d = parseItemDate(it.itemDate)
          if (!d) return '—'
          try {
            return new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
          } catch {
            return '—'
          }
        }
        case 'itemNumber':
        default:
          return `#${it.id}`
      }
    },
    [nametagKey],
  )

  const visibleItems = useMemo(() => {
    const f = appliedFilters
    const selectedColors = new Set(f.colors)
    const selectedCats = new Set(f.categories.map((x) => String(x).toUpperCase()))
    const selectedSubs = new Set(f.subcategories.map((x) => String(x).toUpperCase()))
    const selectedAcq = new Set(f.acquisitionMethods)
    const selectedCond = new Set(f.conditions)
    const selectedWeather = new Set(f.weather)
    const selectedSeasons = new Set(f.seasons)

    function matches(it: Item) {
      // Multi-choice filters: if the filter list is empty, it doesn't constrain.
      if (f.colors.length) {
        const itemColors = new Set((it.colors ?? []).map(String))
        let ok = false
        for (const c of selectedColors) {
          if (itemColors.has(c)) {
            ok = true
            break
          }
        }
        if (!ok) return false
      }
      if (f.categories.length) {
        const cat = String(it.category ?? '').toUpperCase()
        if (!selectedCats.has(cat)) return false
      }
      if (f.subcategories.length) {
        const sub = String(it.subcategory ?? '').toUpperCase()
        if (!selectedSubs.has(sub)) return false
      }
      const extra = (it.extra && typeof it.extra === 'object' ? it.extra : {}) as NonNullable<Item['extra']>
      if (f.acquisitionMethods.length) {
        const m = String((extra as any).acquisitionMethod ?? '')
        if (!selectedAcq.has(m)) return false
      }
      if (f.conditions.length) {
        const c = String((extra as any).condition ?? '')
        if (!selectedCond.has(c)) return false
      }
      if (f.weather.length) {
        const w = Array.isArray((extra as any).weather) ? (extra as any).weather.map(String) : []
        const wSet = new Set(w)
        let ok = false
        for (const tag of selectedWeather) {
          if (wSet.has(tag)) {
            ok = true
            break
          }
        }
        if (!ok) return false
      }
      if (f.seasons.length) {
        const s = Array.isArray((extra as any).seasons) ? (extra as any).seasons.map(String) : []
        const sSet = new Set(s)
        let ok = false
        for (const tag of selectedSeasons) {
          if (sSet.has(tag)) {
            ok = true
            break
          }
        }
        if (!ok) return false
      }
      if (f.secondHand !== 'any') {
        const sh = Boolean((extra as any).secondHand ?? false)
        if (f.secondHand === 'yes' && !sh) return false
        if (f.secondHand === 'no' && sh) return false
      }
      return true
    }

    const filtered = sortedItems.filter(matches)

    function cmpStr(a: string, b: string) {
      return a.localeCompare(b, undefined, { sensitivity: 'base' })
    }

    const defaultDir: Record<SortKey, 1 | -1> = {
      recentlyAdded: -1,
      datePurchased: -1,
      price: 1,
      wears: -1,
      itemType: 1,
      color: 1,
      costPerWear: 1,
    }

    filtered.sort((a, b) => {
      const base = defaultDir[sortKey] ?? 1
      const dir = sortReversed ? (base * -1 as 1 | -1) : base
      switch (sortKey) {
        case 'recentlyAdded': {
          // id is monotonically increasing for a user's items.
          return (a.id - b.id) * dir
        }
        case 'datePurchased': {
          const av = parseItemDate(a.itemDate)
          const bv = parseItemDate(b.itemDate)
          return (av - bv) * dir || (a.id - b.id) * -1
        }
        case 'price': {
          const av = Number(a.price) || 0
          const bv = Number(b.price) || 0
          return (av - bv) * dir || (a.id - b.id) * -1
        }
        case 'wears': {
          const av = Number(a.wears) || 0
          const bv = Number(b.wears) || 0
          return (av - bv) * dir || (a.id - b.id) * -1
        }
        case 'itemType': {
          const ac = closetLabel(a.category)
          const bc = closetLabel(b.category)
          const cat = cmpStr(ac, bc)
          if (cat !== 0) return cat * dir
          const as = closetLabel(a.subcategory)
          const bs = closetLabel(b.subcategory)
          const sub = cmpStr(as, bs)
          return sub * dir || (a.id - b.id) * -1
        }
        case 'color': {
          const ac = closetLabel((a.colors?.[0] ?? '') as string)
          const bc = closetLabel((b.colors?.[0] ?? '') as string)
          const c = cmpStr(ac, bc)
          return c * dir || (a.id - b.id) * -1
        }
        case 'costPerWear': {
          const av = costPerWear(Number(a.price) || 0, Number(a.wears) || 0)
          const bv = costPerWear(Number(b.price) || 0, Number(b.wears) || 0)
          // Items with 0 wears sort last
          if (av == null && bv == null) return (a.id - b.id) * -1
          if (av == null) return 1
          if (bv == null) return -1
          return (av - bv) * dir || (a.id - b.id) * -1
        }
      }
    })

    return filtered
  }, [appliedFilters, sortedItems, sortKey, sortReversed])

  const subcategoryOptions = SUBCATEGORIES_BY_CATEGORY[form.category] ?? []

  function resetPhotoSession() {
    setPhotoOriginalFile(null)
    setBgModelUsed('isnet')
    setBgTuning('balanced')
    setPhotoMessage(null)
    setRemovingBg(false)
    setPhotoEditOpen(false)
    setPhotoEditSrc(null)
    setPhotoEditOriginalSrc(null)
  }

  function closeItemModal() {
    setModalOpen(false)
    resetPhotoSession()
  }

  function openAddModal() {
    setForm(defaultForm())
    setMode('create')
    setEditingId(null)
    resetPhotoSession()
    setTab('details')
    setModalOpen(true)
  }

  function openEditModal(it: Item) {
    const cents = Math.max(0, Math.round((Number(it.price) || 0) * 100))
    const purchasedDate =
      it.itemDate && String(it.itemDate).length >= 10 ? String(it.itemDate).slice(0, 10) : ''
    const extra = (it.extra && typeof it.extra === 'object' ? it.extra : {}) as NonNullable<Item['extra']>
    setForm({
      name: it.name ?? '',
      selectedColors: Array.isArray(it.colors) ? it.colors : [],
      category: (String(it.category || 'TOP').toUpperCase() as ClosetCategoryId) ?? 'TOP',
      subcategory: String(it.subcategory || 'BLOUSE').toUpperCase(),
      priceCents: String(cents),
      wears: String(it.wears ?? 0),
      photoDataUrl: it.photoDataUrl ?? null,
      purchasedDate,
      acquisitionMethod: String(extra.acquisitionMethod ?? ''),
      secondHand: Boolean(extra.secondHand ?? false),
      weather: Array.isArray(extra.weather) ? extra.weather.map((w) => String(w)) : [],
      seasons: Array.isArray((extra as any).seasons)
        ? (extra as any).seasons.map((s: unknown) => String(s))
        : extra && (extra as any).season
          ? [String((extra as any).season)]
          : [],
      size: String(extra.size ?? ''),
      brand: String(extra.brand ?? ''),
      condition: String(extra.condition ?? ''),
      locationPurchased: String((extra as any).locationPurchased ?? (extra as any).location ?? ''),
      notes: String(extra.notes ?? ''),
      archived: Boolean(it.archived ?? false),
      createdAt: it.createdAt ?? null,
    })
    setMode('edit')
    setEditingId(it.id)
    resetPhotoSession()
    setTab('details')
    setModalOpen(true)
  }

  async function onPickPhoto(file: File | null, fileInput: HTMLInputElement | null) {
    if (!file) return
    setPhotoMessage(null)
    setRemovingBg(true)
    try {
      const usable = await ensureBrowserReadableImage(file)
      setPhotoOriginalFile(usable)
      setPhotoEditOriginalSrc(await fileToDataUrl(usable))
      const { dataUrl, removed, modelUsed } = await removeBackgroundToDataUrl(usable, {
        model: 'isnet',
        device: 'gpu',
        tuning: bgTuning,
      })
      setBgModelUsed(modelUsed)
      setPhotoEditSrc(dataUrl)
      setPhotoEditOpen(true)
      setPhotoMessage(
        removed
          ? null
          : 'Background removal is unavailable right now. You can still crop and rotate your photo.',
      )
    } catch (e) {
      setPhotoMessage(
        e instanceof Error ? e.message : 'Could not load that photo. Try JPEG or PNG.',
      )
      setPhotoOriginalFile(null)
      setPhotoEditOriginalSrc(null)
      setPhotoEditSrc(null)
      setPhotoEditOpen(false)
    } finally {
      setRemovingBg(false)
      // Same file twice does not fire change unless we clear the value.
      if (fileInput) fileInput.value = ''
    }
  }

  async function retryBackgroundRemoval() {
    if (!photoOriginalFile) return
    setPhotoMessage(null)
    setRemovingBg(true)
    // Cycle models: quint8 -> fp16 -> isnet (best). We default to isnet, but retry lets people try alternates.
    const next: BgModel =
      bgModelUsed === 'isnet_quint8' ? 'isnet_fp16' : bgModelUsed === 'isnet_fp16' ? 'isnet' : 'isnet_fp16'
    try {
      const { dataUrl, removed, modelUsed } = await removeBackgroundToDataUrl(photoOriginalFile, {
        model: next,
        device: 'gpu',
        tuning: bgTuning,
      })
      setBgModelUsed(modelUsed)
      setPhotoEditSrc(dataUrl)
      setPhotoEditOriginalSrc(await fileToDataUrl(photoOriginalFile))
      setPhotoEditOpen(true)
      setPhotoMessage(
        removed
          ? null
          : 'Background removal is unavailable right now. You can still crop and rotate your photo.',
      )
    } finally {
      setRemovingBg(false)
    }
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (form.selectedColors.length === 0) {
      setError('Choose at least one color.')
      return
    }
    setSaving(true)
    setError(null)
    try {
      const payload = buildPayload()
      if (mode === 'edit' && editingId != null) {
        await updateItem(editingId, payload)
      } else {
        await createItem(payload)
      }
      setForm(defaultForm())
      closeItemModal()
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    } finally {
      setSaving(false)
    }
  }

  const selectedColorSet = useMemo(() => new Set(form.selectedColors), [form.selectedColors])

  function buildPayload(overrides?: { archived?: boolean }) {
    const price = (parseInt(form.priceCents.replace(/\D/g, ''), 10) || 0) / 100
    const extra = {
      acquisitionMethod: form.acquisitionMethod || undefined,
      secondHand: form.acquisitionMethod === 'Bought' ? Boolean(form.secondHand) : undefined,
      weather: form.weather.length ? form.weather : undefined,
      seasons: form.seasons.length ? form.seasons : undefined,
      size: form.size.trim() || undefined,
      brand: form.brand.trim() || undefined,
      condition: form.condition || undefined,
      locationPurchased: form.locationPurchased.trim() || undefined,
      notes: form.notes.trim() || undefined,
    }
    return {
      name: form.name.trim(),
      colors: [...form.selectedColors],
      category: form.category,
      subcategory: form.subcategory,
      price,
      wears: Number(form.wears) || 0,
      photoDataUrl: form.photoDataUrl,
      itemDate: dateToRfc3339(form.purchasedDate),
      extra,
      archived: overrides?.archived ?? form.archived,
    }
  }

  return (
    <div className="space-y-6">
      <PhotoEditorModal
        open={photoEditOpen}
        imageSrc={photoEditSrc}
        originalSrc={photoEditOriginalSrc}
        onCancel={() => {
          setPhotoEditOpen(false)
          setPhotoEditSrc(null)
        }}
        onSave={(dataUrl) => {
          setForm((f) => ({ ...f, photoDataUrl: dataUrl }))
          setPhotoEditOpen(false)
          setPhotoEditSrc(null)
        }}
      />
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-3xl">
          All items
        </h1>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setViewOpen(true)}
            className="rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] px-4 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
          >
            View
          </button>
          <button
            type="button"
            onClick={() => {
              setDraftFilters(appliedFilters)
              setFiltersOpen(true)
            }}
            className="rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] px-4 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
          >
            Filter
          </button>
          <button
            type="button"
            onClick={() => setSortOpen(true)}
            className="rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] px-4 py-2 text-sm font-medium text-[var(--color-sage)] shadow-sm hover:bg-[var(--color-hover)]"
          >
            Sort
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {error}
        </div>
      )}

      {loading ? (
        <p className="text-sm text-[var(--color-muted)]">Loading items…</p>
      ) : null}

      <ul
        className="grid gap-3 sm:gap-4"
        style={{ gridTemplateColumns: `repeat(${itemsPerRow}, minmax(0, 1fr))` }}
      >
        <li>
          <button
            type="button"
            onClick={openAddModal}
            className="flex aspect-square w-full flex-col items-center justify-center rounded-3xl border-2 border-dashed border-[var(--color-sage)]/40 bg-[var(--color-surface)] text-[var(--color-sage)] shadow-sm transition hover:border-[var(--color-sage)] hover:bg-[var(--color-accent-soft)]"
          >
            <span className="text-4xl font-light leading-none">+</span>
            <span className="mt-2 text-xs font-semibold uppercase tracking-wide">Add item</span>
          </button>
        </li>
        {!loading &&
          visibleItems.map((it) => (
            <li key={it.id}>
              <div className="group relative flex aspect-square h-full flex-col overflow-hidden rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4 shadow-sm ring-1 ring-transparent transition hover:-translate-y-0.5 hover:shadow-md hover:ring-[var(--color-sage)]/25">
                <button
                  type="button"
                  onClick={() => openEditModal(it)}
                  className="absolute right-3 top-3 inline-flex items-center justify-center rounded-full border border-[var(--color-line)] bg-[var(--color-paper)]/90 p-2 text-[var(--color-muted)] opacity-0 shadow-sm backdrop-blur transition hover:text-[var(--color-ink)] group-hover:opacity-100"
                  aria-label={`Edit ${it.name}`}
                >
                  <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M12 20h9" />
                    <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4 11.5-11.5z" />
                  </svg>
                </button>
                <p className="text-[10px] font-semibold uppercase tracking-wide text-[var(--color-sage)]">
                  {nametagText(it)}
                </p>
                {it.photoDataUrl ? (
                  <div className="mt-2 flex flex-1 items-center justify-center rounded-2xl bg-[var(--color-surface)] p-2">
                    <img
                      src={it.photoDataUrl}
                      alt={it.name}
                      className="block max-h-full max-w-full rounded-xl object-contain object-center"
                      loading="lazy"
                    />
                  </div>
                ) : null}
                <h2 className="mt-1 line-clamp-2 text-sm font-semibold leading-snug text-[var(--color-ink)] sm:text-base">
                  {it.name}
                </h2>
                <p className="mt-1 line-clamp-1 text-xs text-[var(--color-muted)]">
                  {closetLabel(it.subcategory)}
                </p>
                <div className="mt-auto flex flex-wrap gap-1 pt-2">
                  {it.colors.slice(0, 4).map((c) => (
                    <span
                      key={`${it.id}-${c}`}
                      className="inline-flex max-w-full items-center gap-1 truncate rounded-full bg-[var(--color-surface)] py-0.5 pl-1 pr-2 text-[10px] text-[var(--color-sage-muted)] ring-1 ring-[var(--color-line)]"
                    >
                      <span
                        className="h-3.5 w-3.5 shrink-0 rounded-sm ring-1 ring-black/10"
                        style={{ background: closetColorSwatch(c) }}
                        aria-hidden
                      />
                      <span className="truncate">{closetLabel(c)}</span>
                    </span>
                  ))}
                  {it.colors.length > 4 ? (
                    <span className="text-[10px] text-[var(--color-muted)]">+{it.colors.length - 4}</span>
                  ) : null}
                </div>
                <div className="mt-2 flex justify-between text-[10px] text-[var(--color-muted)]">
                  <span>${Number(it.price).toFixed(0)}</span>
                  <span>{it.wears}×</span>
                </div>
              </div>
            </li>
          ))}
      </ul>

      {viewOpen ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="View options"
          onClick={() => setViewOpen(false)}
        >
          <div
            className="w-full max-w-md overflow-hidden rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] shadow-xl"
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
            <div className="space-y-5 p-5">
              <label className="block text-xs font-medium text-[var(--color-muted)]">
                Items per row
                <div className="mt-2 flex items-center gap-3">
                  <input
                    type="range"
                    min={2}
                    max={6}
                    step={1}
                    value={itemsPerRow}
                    onChange={(e) => setItemsPerRow(Number(e.target.value))}
                    className="w-full"
                  />
                  <span className="w-8 text-right text-sm font-semibold text-[var(--color-ink)]">{itemsPerRow}</span>
                </div>
              </label>

              <label className="block text-xs font-medium text-[var(--color-muted)]">
                Item nametag
                <select
                  value={nametagKey}
                  onChange={(e) => setNametagKey(e.target.value as NametagKey)}
                  className="mt-2 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                >
                  <option value="name">Name</option>
                  <option value="price">Price</option>
                  <option value="costPerWear">Cost per wear</option>
                  <option value="wears">Wears</option>
                  <option value="brand">Brand</option>
                  <option value="datePurchased">Date purchased</option>
                  <option value="itemNumber">Item number</option>
                </select>
              </label>
            </div>
          </div>
        </div>
      ) : null}

      {filtersOpen ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="Filter items"
          onClick={() => setFiltersOpen(false)}
        >
          <div
            className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-2">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">Filter items</h2>
              <button
                type="button"
                onClick={() => setFiltersOpen(false)}
                className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
              >
                Close
              </button>
            </div>

            <div className="mt-5 space-y-6">
              <div className="grid gap-5 sm:grid-cols-2">
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
                <MultiSelectDropdown
                  label="Acquisition"
                  options={ACQUISITION_METHODS.map((m) => ({ id: m, label: m }))}
                  selected={draftFilters.acquisitionMethods}
                  setSelected={(next) => setDraftFilters((f) => ({ ...f, acquisitionMethods: next }))}
                />
                <MultiSelectDropdown
                  label="Condition"
                  options={CONDITIONS.map((c) => ({ id: c, label: c }))}
                  selected={draftFilters.conditions}
                  setSelected={(next) => setDraftFilters((f) => ({ ...f, conditions: next }))}
                />
                <MultiSelectDropdown
                  label="Weather"
                  options={WEATHER_TAGS.map((t) => ({ id: t, label: t }))}
                  selected={draftFilters.weather}
                  setSelected={(next) => setDraftFilters((f) => ({ ...f, weather: next }))}
                />
                <MultiSelectDropdown
                  label="Seasons"
                  options={SEASONS.map((s) => ({ id: s, label: s }))}
                  selected={draftFilters.seasons}
                  setSelected={(next) => setDraftFilters((f) => ({ ...f, seasons: next }))}
                />
              </div>

              <div>
                <div className="text-xs font-medium text-[var(--color-muted)]">Second-hand</div>
                <div className="mt-2 flex gap-2">
                  {(
                    [
                      ['any', 'Any'],
                      ['yes', 'Yes'],
                      ['no', 'No'],
                    ] as const
                  ).map(([id, label]) => {
                    const on = draftFilters.secondHand === id
                    return (
                      <button
                        key={id}
                        type="button"
                        onClick={() => setDraftFilters((f) => ({ ...f, secondHand: id }))}
                        className={`rounded-full px-4 py-2 text-sm font-semibold ring-1 transition ${
                          on
                            ? 'bg-[var(--color-sage)] text-white ring-[var(--color-sage)]'
                            : 'bg-[var(--color-paper)] text-[var(--color-ink)] ring-[var(--color-line)] hover:bg-[var(--color-hover)]'
                        }`}
                      >
                        {label}
                      </button>
                    )
                  })}
                </div>
              </div>

              <div className="flex gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setDraftFilters(EMPTY_FILTERS)}
                  className="flex-1 rounded-full border border-[var(--color-line)] py-2.5 text-sm font-semibold text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
                >
                  Clear filters
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setAppliedFilters(draftFilters)
                    setFiltersOpen(false)
                  }}
                  className="flex-1 rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md"
                >
                  Save filters
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {sortOpen ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="Sort items"
          onClick={() => setSortOpen(false)}
        >
          <div
            className="w-full max-w-md overflow-hidden rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-[var(--color-line)] px-5 py-4">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">Sort</h2>
              <button
                type="button"
                onClick={() => setSortOpen(false)}
                className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
              >
                Close
              </button>
            </div>
            <div className="space-y-3 p-5">
              {(
                [
                  ['recentlyAdded', 'Recently added'],
                  ['datePurchased', 'Date purchased'],
                  ['price', 'Price'],
                  ['wears', 'Wears'],
                  ['itemType', 'Item type'],
                  ['color', 'Color'],
                  ['costPerWear', 'Cost per wear'],
                ] as const
              ).map(([k, label]) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => {
                    setSortKey(k)
                    setSortReversed(false)
                    setSortOpen(false)
                  }}
                  className={`flex w-full items-center justify-between rounded-2xl border px-4 py-3 text-left text-sm font-semibold transition ${
                    sortKey === k
                      ? 'border-[var(--color-sage)] bg-[var(--color-surface)] text-[var(--color-ink)]'
                      : 'border-[var(--color-line)] bg-[var(--color-paper)] text-[var(--color-ink)] hover:bg-[var(--color-hover)]'
                  }`}
                >
                  <span>{label}</span>
                  {sortKey === k ? (
                    <button
                      type="button"
                      onClick={(e) => {
                        e.preventDefault()
                        e.stopPropagation()
                        setSortReversed((v) => !v)
                      }}
                      className="inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-semibold text-[var(--color-muted)] hover:bg-[var(--color-paper)]"
                      aria-label="Reverse sort direction"
                      title="Reverse"
                    >
                      <span className="text-[10px]">{sortReversed ? '↑' : '↓'}</span>
                    </button>
                  ) : (
                    <span className="text-xs text-[var(--color-muted)]" />
                  )}
                </button>
              ))}
            </div>
          </div>
        </div>
      ) : null}

      {modalOpen ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-labelledby="add-item-title"
          onClick={closeItemModal}
        >
          <div
            className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-2">
              <h2 id="add-item-title" className="text-lg font-semibold text-[var(--color-sage)]">
                {mode === 'edit' ? 'Edit item' : 'New item'}
              </h2>
              <button
                type="button"
                onClick={closeItemModal}
                className="rounded-full px-2 py-1 text-sm text-[var(--color-muted)] hover:bg-[var(--color-hover)]"
              >
                Close
              </button>
            </div>
            <div className="mt-4 flex items-center gap-2 rounded-2xl bg-[var(--color-surface)] p-1">
              <button
                type="button"
                onClick={() => setTab('details')}
                className={`flex-1 rounded-xl px-3 py-2 text-sm font-semibold transition ${
                  tab === 'details'
                    ? 'bg-[var(--color-paper)] text-[var(--color-ink)] shadow-sm'
                    : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
                }`}
              >
                Details
              </button>
              <button
                type="button"
                onClick={() => setTab('extra')}
                className={`flex-1 rounded-xl px-3 py-2 text-sm font-semibold transition ${
                  tab === 'extra'
                    ? 'bg-[var(--color-paper)] text-[var(--color-ink)] shadow-sm'
                    : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
                }`}
              >
                Extra info
              </button>
            </div>

            <form className="mt-4 space-y-4" onSubmit={onSubmit}>
              {tab === 'details' ? (
                <>
              <div>
                <span className="text-xs font-medium text-[var(--color-muted)]">Photo</span>
                <div className="mt-2 grid grid-cols-1 gap-3 sm:grid-cols-[96px_1fr] sm:items-start">
                  <div className="flex h-24 w-24 items-center justify-center overflow-hidden rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)]">
                    {form.photoDataUrl ? (
                      <img
                        src={form.photoDataUrl}
                        alt=""
                        className="block max-h-full max-w-full object-contain object-center"
                      />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center text-[10px] text-[var(--color-muted)]">
                        No photo
                      </div>
                    )}
                  </div>
                  <div>
                    <input
                      type="file"
                      accept="image/*,image/heic,image/heif,.heic,.heif"
                      disabled={saving}
                      onChange={(e) => void onPickPhoto(e.target.files?.[0] ?? null, e.target)}
                      className="block w-full text-sm text-[var(--color-muted)] file:mr-3 file:rounded-full file:border-0 file:bg-[var(--color-surface)] file:px-4 file:py-2 file:text-sm file:font-semibold file:text-[var(--color-ink)] hover:file:bg-[var(--color-hover)] disabled:opacity-50"
                    />
                    {removingBg ? (
                      <p className="mt-2 text-xs text-[var(--color-muted)]">Preparing photo (HEIC conversion / background removal)…</p>
                    ) : null}
                    {photoMessage ? (
                      <p className="mt-2 text-xs text-[var(--color-sage)]">{photoMessage}</p>
                    ) : null}
                    {photoOriginalFile && !removingBg ? (
                      <div className="mt-2 flex flex-wrap items-center gap-2">
                        <label className="text-xs font-medium text-[var(--color-muted)]">
                          Removal
                          <select
                            value={bgTuning}
                            onChange={(e) => setBgTuning(e.target.value as BgPostprocessTuning)}
                            className="ml-2 rounded-lg border border-[var(--color-line)] bg-[var(--color-paper)] px-2 py-1 text-xs font-semibold text-[var(--color-ink)] outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                          >
                            <option value="balanced">Balanced</option>
                            <option value="cleaner">Cleaner background</option>
                            <option value="preserveEdges">Preserve edges</option>
                          </select>
                        </label>
                        <button
                          type="button"
                          onClick={() => void retryBackgroundRemoval()}
                          className="text-xs font-semibold text-[var(--color-sage)] hover:underline"
                        >
                          Try again
                        </button>
                      </div>
                    ) : null}
                    {mode === 'edit' && form.photoDataUrl ? (
                      <button
                        type="button"
                        onClick={() => setForm((f) => ({ ...f, photoDataUrl: null }))}
                        className="mt-2 text-xs font-semibold text-[var(--color-sage)] hover:underline"
                      >
                        Remove photo
                      </button>
                    ) : null}
                  </div>
                </div>
              </div>

              <label className="block text-xs font-medium text-[var(--color-muted)]">
                Name
                <input
                  required
                  value={form.name}
                  onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
                  className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                  placeholder="e.g. Linen blazer"
                />
              </label>

              {mode === 'edit' && form.createdAt ? (
                <p className="text-xs text-[var(--color-muted)]">
                  Added to closet{' '}
                  <span className="font-medium text-[var(--color-ink)]">{formatAddedToCloset(form.createdAt)}</span>
                </p>
              ) : null}

              <div>
                <span className="text-xs font-medium text-[var(--color-muted)]">Colors</span>
                {form.selectedColors.length > 0 ? (
                  <ul className="mt-2 flex flex-wrap gap-2">
                    {form.selectedColors.map((id) => (
                      <li key={id}>
                        <span className="inline-flex items-center gap-2 rounded-full border border-[var(--color-line)] bg-[var(--color-surface)] py-1 pl-1.5 pr-1 text-xs font-medium text-[var(--color-ink)]">
                          <span
                            className="h-4 w-4 shrink-0 rounded-md ring-1 ring-black/10"
                            style={{ background: closetColorSwatch(id) }}
                            aria-hidden
                          />
                          <span className="max-w-[140px] truncate">{closetLabel(id)}</span>
                          <button
                            type="button"
                            className="rounded-full px-1.5 py-0.5 text-[var(--color-muted)] hover:bg-[var(--color-paper)] hover:text-[var(--color-ink)]"
                            aria-label={`Remove ${id}`}
                            onClick={() =>
                              setForm((f) => ({
                                ...f,
                                selectedColors: f.selectedColors.filter((c) => c !== id),
                              }))
                            }
                          >
                            ×
                          </button>
                        </span>
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p className="mt-2 text-xs text-[var(--color-muted)]">No colors yet.</p>
                )}
                <ClosetColorAddSelect
                  omit={selectedColorSet}
                  disabled={saving}
                  onAdd={(id) =>
                    setForm((f) => ({
                      ...f,
                      selectedColors: f.selectedColors.includes(id) ? f.selectedColors : [...f.selectedColors, id],
                    }))
                  }
                />
              </div>

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <label className="block text-xs font-medium text-[var(--color-muted)]">
                  Type
                  <select
                    value={form.category}
                    onChange={(e) => {
                      const category = e.target.value as ClosetCategoryId
                      const subs = SUBCATEGORIES_BY_CATEGORY[category] ?? []
                      setForm((f) => ({
                        ...f,
                        category,
                        subcategory: subs[0] ?? f.subcategory,
                      }))
                    }}
                    className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                  >
                    {CLOSET_CATEGORIES.map((c) => (
                      <option key={c} value={c}>
                        {closetLabel(c)}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="block text-xs font-medium text-[var(--color-muted)]">
                  Subtype
                  <select
                    value={form.subcategory}
                    onChange={(e) => setForm((f) => ({ ...f, subcategory: e.target.value }))}
                    className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                  >
                    {subcategoryOptions.map((s) => (
                      <option key={s} value={s}>
                        {closetLabel(s)}
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <label className="block text-xs font-medium text-[var(--color-muted)]">
                  Price
                  <div className="mt-1 flex items-center gap-2 rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus-within:ring-2">
                    <span className="select-none font-semibold text-[var(--color-ink)]">$</span>
                    <input
                      type="text"
                      inputMode="numeric"
                      value={formatCents(form.priceCents)}
                      onChange={(e) => {
                        const digits = e.target.value.replace(/\D/g, '')
                        setForm((f) => ({ ...f, priceCents: digits || '0' }))
                      }}
                      onKeyDown={(e) => {
                        // Make backspace behave like removing the last typed digit.
                        if (e.key === 'Backspace') {
                          e.preventDefault()
                          setForm((f) => {
                            const d = (f.priceCents || '0').replace(/\D/g, '')
                            const next = d.length <= 1 ? '0' : d.slice(0, -1)
                            return { ...f, priceCents: next }
                          })
                        }
                      }}
                      className="w-full bg-transparent text-[var(--color-ink)] outline-none"
                      aria-label="Price"
                      autoComplete="off"
                    />
                  </div>
                  <div className="mt-2 text-xs text-[var(--color-muted)]">
                    Cost per wear:{' '}
                    {(() => {
                      const price = (parseInt(form.priceCents.replace(/\D/g, ''), 10) || 0) / 100
                      const wears = parseInt(String(form.wears || '0'), 10) || 0
                      const cpw = costPerWear(price, wears)
                      return cpw == null ? '—' : `$${cpw.toFixed(2)}`
                    })()}
                  </div>
                </label>
                <label className="block text-xs font-medium text-[var(--color-muted)]">
                  Wears
                  <input
                    type="number"
                    min={0}
                    value={form.wears}
                    onChange={(e) => setForm((f) => ({ ...f, wears: e.target.value }))}
                    className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                  />
                </label>
              </div>
                </>
              ) : (
                <>
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Date purchased
                      <input
                        type="date"
                        value={form.purchasedDate}
                        onChange={(e) => setForm((f) => ({ ...f, purchasedDate: e.target.value }))}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      />
                    </label>
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Acquisition
                      <select
                        value={form.acquisitionMethod}
                        onChange={(e) => setForm((f) => ({ ...f, acquisitionMethod: e.target.value }))}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      >
                        <option value="">Select…</option>
                        {ACQUISITION_METHODS.map((m) => (
                          <option key={m} value={m}>
                            {m}
                          </option>
                        ))}
                      </select>
                    </label>
                  </div>

                  {form.acquisitionMethod === 'Bought' ? (
                    <label className="flex items-center justify-between rounded-2xl border border-[var(--color-line)] bg-[var(--color-paper)] px-4 py-3">
                      <span className="text-sm font-medium text-[var(--color-ink)]">Second-hand</span>
                      <input
                        type="checkbox"
                        checked={form.secondHand}
                        onChange={(e) => setForm((f) => ({ ...f, secondHand: e.target.checked }))}
                        className="h-5 w-5 accent-[var(--color-sage)]"
                      />
                    </label>
                  ) : null}

                  <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-paper)] px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">Weather</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {WEATHER_TAGS.map((t) => {
                        const on = form.weather.includes(t)
                        return (
                          <button
                            key={t}
                            type="button"
                            onClick={() =>
                              setForm((f) => ({
                                ...f,
                                weather: on ? f.weather.filter((x) => x !== t) : [...f.weather, t],
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

                  <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-paper)] px-4 py-3">
                    <div className="text-xs font-medium text-[var(--color-muted)]">Season</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {SEASONS.map((s) => {
                        const on = form.seasons.includes(s)
                        return (
                          <button
                            key={s}
                            type="button"
                            onClick={() =>
                              setForm((f) => ({
                                ...f,
                                seasons: on ? f.seasons.filter((x) => x !== s) : [...f.seasons, s],
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

                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Size
                      <input
                        value={form.size}
                        onChange={(e) => setForm((f) => ({ ...f, size: e.target.value }))}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                        placeholder="e.g. S, 6, 28, 8.5"
                      />
                    </label>
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Brand
                      <input
                        value={form.brand}
                        onChange={(e) => setForm((f) => ({ ...f, brand: e.target.value }))}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                        placeholder="Optional"
                      />
                    </label>
                  </div>

                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Condition
                      <select
                        value={form.condition}
                        onChange={(e) => setForm((f) => ({ ...f, condition: e.target.value }))}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      >
                        <option value="">Select…</option>
                        {CONDITIONS.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="block text-xs font-medium text-[var(--color-muted)]">
                      Location purchased
                      <input
                        value={form.locationPurchased}
                        onChange={(e) => setForm((f) => ({ ...f, locationPurchased: e.target.value }))}
                        className="mt-1 w-full rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                        placeholder="Optional"
                      />
                    </label>
                  </div>

                  <label className="block text-xs font-medium text-[var(--color-muted)]">
                    Notes
                    <textarea
                      value={form.notes}
                      onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                      rows={4}
                      className="mt-1 w-full resize-none rounded-xl border border-[var(--color-line)] bg-[var(--color-paper)] px-3 py-2 text-sm outline-none ring-[var(--color-sage)]/30 focus:ring-2"
                      placeholder="Fit, care instructions, where it’s from, or anything you want to remember."
                    />
                  </label>
                </>
              )}
              {mode === 'edit' && editingId != null ? (
                <div className="grid grid-cols-3 gap-2 pt-2">
                  <button
                    type="button"
                    disabled={saving || removingBg}
                    onClick={async () => {
                      if (!confirm('Delete this item? This cannot be undone.')) return
                      setSaving(true)
                      setError(null)
                      try {
                        await deleteItem(editingId)
                        closeItemModal()
                        await load()
                      } catch (err) {
                        setError(err instanceof Error ? err.message : 'Could not delete item')
                      } finally {
                        setSaving(false)
                      }
                    }}
                    className="rounded-full border border-red-300/40 bg-[var(--color-paper)] py-2.5 text-sm font-semibold text-red-300 hover:bg-red-900/30 disabled:opacity-60"
                  >
                    Delete
                  </button>
                  <button
                    type="button"
                    disabled={saving || removingBg}
                    onClick={async () => {
                      const next = !form.archived
                      if (!confirm(next ? 'Archive this item?' : 'Unarchive this item?')) return
                      setSaving(true)
                      setError(null)
                      try {
                        setForm((f) => ({ ...f, archived: next }))
                        await updateItem(editingId, buildPayload({ archived: next }))
                        closeItemModal()
                        await load()
                      } catch (err) {
                        setError(err instanceof Error ? err.message : 'Could not update item')
                      } finally {
                        setSaving(false)
                      }
                    }}
                    className="rounded-full border border-[var(--color-line)] bg-[var(--color-paper)] py-2.5 text-sm font-semibold text-[var(--color-sage)] hover:bg-[var(--color-hover)] disabled:opacity-60"
                  >
                    {form.archived ? 'Unarchive' : 'Archive'}
                  </button>
                  <button
                    type="submit"
                    disabled={saving || removingBg}
                    className="rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-60"
                  >
                    {saving ? 'Saving…' : 'Save'}
                  </button>
                </div>
              ) : (
                <div className="pt-2">
                  <button
                    type="submit"
                    disabled={saving || removingBg}
                    className="w-full rounded-full bg-[var(--color-sage)] py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-60"
                  >
                    {saving ? 'Saving…' : 'Save'}
                  </button>
                </div>
              )}
            </form>
          </div>
        </div>
      ) : null}
    </div>
  )
}
