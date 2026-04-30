import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { OC_GOOGLE_ID_TOKEN_KEY, setAuthTokenGetter } from '../authHeaders'

type AuthValue = {
  token: string | null
  setToken: (t: string | null) => void
  logout: () => void
  isAuthenticated: boolean
}

const AuthContext = createContext<AuthValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setTokenState] = useState<string | null>(() =>
    typeof sessionStorage !== 'undefined' ? sessionStorage.getItem(OC_GOOGLE_ID_TOKEN_KEY) : null,
  )

  const setToken = useCallback((t: string | null) => {
    if (typeof sessionStorage !== 'undefined') {
      if (t) sessionStorage.setItem(OC_GOOGLE_ID_TOKEN_KEY, t)
      else sessionStorage.removeItem(OC_GOOGLE_ID_TOKEN_KEY)
    }
    setAuthTokenGetter(() => t)
    setTokenState(t)
  }, [])

  const logout = useCallback(() => {
    setToken(null)
  }, [setToken])

  useEffect(() => {
    setAuthTokenGetter(() => token)
  }, [token])

  const value = useMemo(
    () => ({
      token,
      setToken,
      logout,
      isAuthenticated: Boolean(token),
    }),
    [token, setToken, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const v = useContext(AuthContext)
  if (!v) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return v
}
