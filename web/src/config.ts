const trim = (v: string | undefined) => (v ?? '').replace(/\/$/, '')

export type ApiService = 'items' | 'outfits' | 'schedule'

/**
 * Absolute API URL. In production always uses `window.location.origin` so nothing baked
 * from a dev `.env` can break requests (localhost / http / wrong host → "Failed to fetch").
 * In dev, uses `VITE_*_API` per service.
 */
export function apiUrl(service: ApiService, path: string): string {
  const p = path.startsWith('/') ? path : `/${path}`
  if (import.meta.env.PROD) {
    if (typeof window !== 'undefined') {
      return new URL(p, window.location.origin).href
    }
    return p
  }
  const base =
    service === 'items'
      ? trim(import.meta.env.VITE_ITEMS_API)
      : service === 'outfits'
        ? trim(import.meta.env.VITE_OUTFITS_API)
        : trim(import.meta.env.VITE_SCHEDULE_API)
  return `${base}${p}`
}
