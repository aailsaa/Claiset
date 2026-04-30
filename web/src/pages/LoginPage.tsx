import { GoogleLogin } from '@react-oauth/google'
import { useEffect } from 'react'
import { flushSync } from 'react-dom'
import { useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'

const clientId = import.meta.env.VITE_GOOGLE_CLIENT_ID ?? ''

function postLoginPath(state: unknown): string {
  const raw = (state as { from?: string } | null)?.from
  if (raw === '/stats' || raw === '/outfits' || raw === '/calendar') return raw
  return '/closet'
}

export function LoginPage() {
  const { isAuthenticated, setToken } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  useEffect(() => {
    if (isAuthenticated) {
      navigate('/closet', { replace: true })
    }
  }, [isAuthenticated, navigate])

  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-4">
      <div className="w-full max-w-md rounded-[2rem] border border-[var(--color-line)] bg-white p-10 shadow-lg">
        <h1 className="text-center text-3xl font-bold tracking-tight text-[var(--color-sage)] sm:text-4xl">
          Online Closet
        </h1>
        <p className="mt-3 text-center text-sm text-[var(--color-muted)]">
          Sign in with Google to open your closet, outfits, and calendar.
        </p>

        {!clientId ? (
          <p className="mt-8 rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4 text-center text-sm text-[var(--color-muted)]">
            Sign-in is temporarily unavailable. Please try again later.
          </p>
        ) : (
          <div className="mt-10 flex justify-center">
            <GoogleLogin
              onSuccess={(cred) => {
                const jwt = cred.credential
                if (jwt) {
                  // Commit auth before navigating so protected routes and data fetches see the token immediately.
                  flushSync(() => {
                    setToken(jwt)
                  })
                  navigate(postLoginPath(location.state), { replace: true })
                }
              }}
              onError={() => {
                console.error('Google sign-in failed')
              }}
              useOneTap={false}
            />
          </div>
        )}
      </div>
    </div>
  )
}
