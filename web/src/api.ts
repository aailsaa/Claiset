import { authHeaders } from './authHeaders'
import { apiUrl } from './config'
import type { Assignment, Item, Outfit, OutfitPicture } from './types'

async function apiFetch(input: string, init?: RequestInit): Promise<Response> {
  try {
    return await fetch(input, init)
  } catch (e) {
    const inner = e instanceof Error ? e.message : String(e)
    throw new Error(`${inner} (${input})`)
  }
}

async function unauthorizedMessage(res: Response): Promise<never> {
  const detail = (await res.text()).trim()
  throw new Error(
    detail
      ? `Session expired or not signed in. (${detail})`
      : 'Session expired or not signed in. Please log in again.',
  )
}

async function parseJson<T>(res: Response): Promise<T> {
  if (res.status === 401) {
    await unauthorizedMessage(res)
  }
  if (!res.ok) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
  return res.json() as Promise<T>
}

function mergeHeaders(h?: HeadersInit): HeadersInit {
  return { ...authHeaders(), ...(h ?? {}) }
}

function normalizeItem(raw: unknown): Item | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Record<string, unknown>
  const id = Number(o.id)
  if (!Number.isFinite(id)) return null
  let colors: string[] = []
  if (Array.isArray(o.colors)) {
    colors = o.colors.map((c) => String(c))
  }
  const price =
    typeof o.price === 'number' && Number.isFinite(o.price)
      ? o.price
      : parseFloat(String(o.price ?? 0)) || 0
  const wears =
    typeof o.wears === 'number' && Number.isFinite(o.wears)
      ? Math.trunc(o.wears)
      : parseInt(String(o.wears ?? 0), 10) || 0
  let createdAt: string | undefined
  if (o.createdAt != null && String(o.createdAt).trim() !== '') {
    const s = String(o.createdAt)
    if (!s.startsWith('0001-01-01')) createdAt = s
  }
  return {
    id,
    name: String(o.name ?? ''),
    colors,
    category: String(o.category ?? ''),
    subcategory: String(o.subcategory ?? ''),
    price,
    wears,
    itemDate: o.itemDate == null ? undefined : String(o.itemDate),
    createdAt,
    photoDataUrl: o.photoDataUrl == null ? undefined : String(o.photoDataUrl),
    extra: o.extra && typeof o.extra === 'object' ? (o.extra as Item['extra']) : undefined,
    archived: typeof o.archived === 'boolean' ? o.archived : undefined,
  }
}

function normalizeOutfitPicture(raw: unknown): OutfitPicture | null {
  if (!raw || typeof raw !== 'object') return null
  const p = raw as Record<string, unknown>
  const id = typeof p.id === 'string' && p.id ? p.id : null
  const dataUrl = typeof p.dataUrl === 'string' && p.dataUrl ? p.dataUrl : null
  const takenAt = typeof p.takenAt === 'string' && p.takenAt ? p.takenAt : null
  if (!id || !dataUrl || !takenAt) return null
  return {
    id,
    dataUrl,
    takenAt,
    backgroundRemoved: p.backgroundRemoved === true,
    wornOnDay: typeof p.wornOnDay === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(p.wornOnDay) ? p.wornOnDay : undefined,
  }
}

function normalizeOutfit(raw: unknown): Outfit | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Record<string, unknown>
  const id = Number(o.id)
  if (!Number.isFinite(id)) return null
  let itemIds: number[] = []
  if (Array.isArray(o.itemIds)) {
    itemIds = o.itemIds.map((x) => Math.trunc(Number(x))).filter((n) => Number.isFinite(n))
  }
  const wears =
    typeof o.wears === 'number' && Number.isFinite(o.wears)
      ? Math.trunc(o.wears)
      : parseInt(String(o.wears ?? 0), 10) || 0
  const coverDataUrl = o.coverDataUrl == null ? undefined : String(o.coverDataUrl)
  const extra = o.extra && typeof o.extra === 'object' ? (o.extra as Outfit['extra']) : undefined
  const layout = Array.isArray(o.layout) ? (o.layout as Outfit['layout']) : undefined
  let pictures: Outfit['pictures'] = undefined
  if (Array.isArray(o.pictures)) {
    const arr = o.pictures.map(normalizeOutfitPicture).filter((x): x is OutfitPicture => x !== null)
    pictures = arr
  }
  return {
    id,
    name: String(o.name ?? ''),
    wears,
    itemIds,
    coverDataUrl,
    extra,
    layout,
    pictures,
  }
}

function normalizeAssignment(raw: unknown): Assignment | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Record<string, unknown>
  const id = Number(o.id)
  const outfitId = Number(o.outfitId)
  if (!Number.isFinite(id) || !Number.isFinite(outfitId)) return null
  return {
    id,
    outfitId,
    day: String(o.day ?? ''),
    notes: o.notes == null ? undefined : String(o.notes),
  }
}

export async function fetchItems(): Promise<Item[]> {
  const res = await apiFetch(apiUrl('items', '/api/v1/items'), { headers: mergeHeaders() })
  const raw = await parseJson<unknown>(res)
  if (!Array.isArray(raw)) return []
  return raw.map(normalizeItem).filter((x): x is Item => x !== null)
}

export async function createItem(body: {
  name: string
  colors: string[]
  category: string
  subcategory: string
  price?: number
  wears?: number
  photoDataUrl?: string | null
  itemDate?: string | null
  extra?: Item['extra'] | null
  archived?: boolean
}): Promise<Item> {
  const res = await apiFetch(apiUrl('items', '/api/v1/items'), {
    method: 'POST',
    headers: mergeHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })
  const raw = await parseJson<unknown>(res)
  const it = normalizeItem(raw)
  if (!it) throw new Error('Invalid item response')
  return it
}

export async function updateItem(
  id: number,
  body: {
    name: string
    colors: string[]
    category: string
    subcategory: string
    price?: number
    wears?: number
    photoDataUrl?: string | null
    itemDate?: string | null
    extra?: Item['extra'] | null
    archived?: boolean
  },
): Promise<Item> {
  const res = await apiFetch(apiUrl('items', `/api/v1/items/${id}`), {
    method: 'PUT',
    headers: mergeHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })
  const raw = await parseJson<unknown>(res)
  const it = normalizeItem(raw)
  if (!it) throw new Error('Invalid item response')
  return it
}

export async function deleteItem(id: number): Promise<void> {
  const res = await apiFetch(apiUrl('items', `/api/v1/items/${id}`), {
    method: 'DELETE',
    headers: mergeHeaders(),
  })
  if (res.status === 401) {
    await unauthorizedMessage(res)
  }
  if (!res.ok && res.status !== 204) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
}

export async function fetchOutfits(): Promise<Outfit[]> {
  const res = await apiFetch(apiUrl('outfits', '/api/v1/outfits'), { headers: mergeHeaders() })
  const raw = await parseJson<unknown>(res)
  if (!Array.isArray(raw)) return []
  return raw.map(normalizeOutfit).filter((x): x is Outfit => x !== null)
}

export async function createOutfit(body: {
  name: string
  itemIds: number[]
  wears?: number
  coverDataUrl?: string | null
  extra?: Outfit['extra'] | null
  layout?: Outfit['layout'] | null
  pictures?: Outfit['pictures'] | null
}): Promise<Outfit> {
  const res = await apiFetch(apiUrl('outfits', '/api/v1/outfits'), {
    method: 'POST',
    headers: mergeHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })
  const raw = await parseJson<unknown>(res)
  const o = normalizeOutfit(raw)
  if (!o) throw new Error('Invalid outfit response')
  return o
}

export async function updateOutfit(
  id: number,
  body: {
    name: string
    itemIds: number[]
    wears?: number
    coverDataUrl?: string | null
    extra?: Outfit['extra'] | null
    layout?: Outfit['layout'] | null
    pictures?: Outfit['pictures'] | null
  },
): Promise<Outfit> {
  const res = await apiFetch(apiUrl('outfits', `/api/v1/outfits/${id}`), {
    method: 'PUT',
    headers: mergeHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })
  const raw = await parseJson<unknown>(res)
  const o = normalizeOutfit(raw)
  if (!o) throw new Error('Invalid outfit response')
  return o
}

export async function deleteOutfit(id: number): Promise<void> {
  const res = await apiFetch(apiUrl('outfits', `/api/v1/outfits/${id}`), {
    method: 'DELETE',
    headers: mergeHeaders(),
  })
  if (res.status === 401) {
    await unauthorizedMessage(res)
  }
  if (!res.ok && res.status !== 204) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
}

export async function fetchAssignments(month: string): Promise<Assignment[]> {
  const q = new URLSearchParams({ month })
  const res = await apiFetch(apiUrl('schedule', `/api/v1/assignments?${q}`), {
    headers: mergeHeaders(),
  })
  const raw = await parseJson<unknown>(res)
  if (!Array.isArray(raw)) return []
  return raw.map(normalizeAssignment).filter((x): x is Assignment => x !== null)
}

export async function createAssignment(body: {
  outfitId: number
  day: string
  notes?: string
}): Promise<Assignment> {
  const res = await apiFetch(apiUrl('schedule', '/api/v1/assignments'), {
    method: 'POST',
    headers: mergeHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })
  const raw = await parseJson<unknown>(res)
  const a = normalizeAssignment(raw)
  if (!a) throw new Error('Invalid assignment response')
  return a
}

export async function deleteAssignment(id: number): Promise<void> {
  const res = await apiFetch(apiUrl('schedule', `/api/v1/assignments/${id}`), {
    method: 'DELETE',
    headers: mergeHeaders(),
  })
  if (res.status === 401) {
    await unauthorizedMessage(res)
  }
  if (!res.ok && res.status !== 204) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
}

