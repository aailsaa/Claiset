/** Same key as AuthProvider uses for sessionStorage (single source for Bearer token). */
export const OC_GOOGLE_ID_TOKEN_KEY = 'oc_google_id_token'

let tokenGetter: () => string | null = () => null

/** Called from AuthProvider whenever the session token changes. */
export function setAuthTokenGetter(fn: () => string | null) {
  tokenGetter = fn
}

/**
 * Reads the ID token from sessionStorage first so requests right after login work:
 * child useEffects can run before AuthProvider's effect updates `tokenGetter`.
 */
export function authHeaders(): Record<string, string> {
  if (typeof sessionStorage !== 'undefined') {
    const fromStore = sessionStorage.getItem(OC_GOOGLE_ID_TOKEN_KEY)?.trim()
    if (fromStore) return { Authorization: `Bearer ${fromStore}` }
  }
  const t = tokenGetter()?.trim()
  if (!t) return {}
  return { Authorization: `Bearer ${t}` }
}
