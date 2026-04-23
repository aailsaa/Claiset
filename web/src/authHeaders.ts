let tokenGetter: () => string | null = () => null

/** Called from AuthProvider whenever the session token changes. */
export function setAuthTokenGetter(fn: () => string | null) {
  tokenGetter = fn
}

export function authHeaders(): Record<string, string> {
  const t = tokenGetter()
  if (!t) return {}
  return { Authorization: `Bearer ${t}` }
}
