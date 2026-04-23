/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ITEMS_API?: string
  readonly VITE_OUTFITS_API?: string
  readonly VITE_SCHEDULE_API?: string
  readonly VITE_GOOGLE_CLIENT_ID?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
