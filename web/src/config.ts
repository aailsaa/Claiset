const trim = (v: string | undefined) => (v ?? '').replace(/\/$/, '')

export const itemsApi = trim(import.meta.env.VITE_ITEMS_API) || 'http://localhost:8081'
export const outfitsApi = trim(import.meta.env.VITE_OUTFITS_API) || 'http://localhost:8082'
export const scheduleApi = trim(import.meta.env.VITE_SCHEDULE_API) || 'http://localhost:8083'
