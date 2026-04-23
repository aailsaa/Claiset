import { authHeaders } from './authHeaders'
import { itemsApi, outfitsApi, scheduleApi } from './config'
import type { Assignment, Item, Outfit } from './types'

async function parseJson<T>(res: Response): Promise<T> {
  if (res.status === 401) {
    throw new Error('Session expired or not signed in. Please log in again.')
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
  return {
    id,
    name: String(o.name ?? ''),
    colors,
    category: String(o.category ?? ''),
    subcategory: String(o.subcategory ?? ''),
    price,
    wears,
    itemDate: o.itemDate == null ? undefined : String(o.itemDate),
    photoDataUrl: o.photoDataUrl == null ? undefined : String(o.photoDataUrl),
    extra: o.extra && typeof o.extra === 'object' ? (o.extra as Item['extra']) : undefined,
    archived: typeof o.archived === 'boolean' ? o.archived : undefined,
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
  return {
    id,
    name: String(o.name ?? ''),
    wears,
    itemIds,
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
  const res = await fetch(`${itemsApi}/api/v1/items`, { headers: mergeHeaders() })
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
  const res = await fetch(`${itemsApi}/api/v1/items`, {
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
  const res = await fetch(`${itemsApi}/api/v1/items/${id}`, {
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
  const res = await fetch(`${itemsApi}/api/v1/items/${id}`, {
    method: 'DELETE',
    headers: mergeHeaders(),
  })
  if (res.status === 401) {
    throw new Error('Session expired or not signed in. Please log in again.')
  }
  if (!res.ok && res.status !== 204) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
}

export async function fetchOutfits(): Promise<Outfit[]> {
  const res = await fetch(`${outfitsApi}/api/v1/outfits`, { headers: mergeHeaders() })
  const raw = await parseJson<unknown>(res)
  if (!Array.isArray(raw)) return []
  return raw.map(normalizeOutfit).filter((x): x is Outfit => x !== null)
}

export async function createOutfit(body: {
  name: string
  itemIds: number[]
}): Promise<Outfit> {
  const res = await fetch(`${outfitsApi}/api/v1/outfits`, {
    method: 'POST',
    headers: mergeHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })
  const raw = await parseJson<unknown>(res)
  const o = normalizeOutfit(raw)
  if (!o) throw new Error('Invalid outfit response')
  return o
}

export async function fetchAssignments(month: string): Promise<Assignment[]> {
  const q = new URLSearchParams({ month })
  const res = await fetch(`${scheduleApi}/api/v1/assignments?${q}`, {
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
  const res = await fetch(`${scheduleApi}/api/v1/assignments`, {
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
  const res = await fetch(`${scheduleApi}/api/v1/assignments/${id}`, {
    method: 'DELETE',
    headers: mergeHeaders(),
  })
  if (res.status === 401) {
    throw new Error('Session expired or not signed in. Please log in again.')
  }
  if (!res.ok && res.status !== 204) {
    const text = await res.text()
    throw new Error(text || res.statusText)
  }
}
