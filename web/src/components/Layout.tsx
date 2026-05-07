import { useEffect, useRef, useState, type ReactNode } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'

const THEME_STORAGE_KEY = 'oc-theme'

const tabClass = ({ isActive }: { isActive: boolean }) =>
  [
    'relative flex-1 px-4 py-3 text-center text-sm font-semibold transition-colors sm:text-base [font-family:var(--font-heading)]',
    isActive
      ? 'text-[var(--color-sage)] after:absolute after:bottom-0 after:left-4 after:right-4 after:h-0.5 after:rounded-full after:bg-[var(--color-sage)]'
      : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]',
  ].join(' ')

type LayoutProps = {
  /** When set (from a parent route), renders instead of <Outlet />. */
  children?: ReactNode
}

export function Layout({ children }: LayoutProps) {
  const navigate = useNavigate()
  const { logout } = useAuth()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [darkMode, setDarkMode] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false
    return localStorage.getItem(THEME_STORAGE_KEY) === 'dark'
  })
  const settingsRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    const root = document.documentElement
    if (darkMode) root.setAttribute('data-theme', 'dark')
    else root.removeAttribute('data-theme')
    localStorage.setItem(THEME_STORAGE_KEY, darkMode ? 'dark' : 'light')
  }, [darkMode])

  useEffect(() => {
    if (!settingsOpen) return
    const onPointerDown = (event: MouseEvent) => {
      if (!settingsRef.current?.contains(event.target as Node)) {
        setSettingsOpen(false)
      }
    }
    window.addEventListener('mousedown', onPointerDown)
    return () => window.removeEventListener('mousedown', onPointerDown)
  }, [settingsOpen])

  return (
    <div className="flex min-h-screen flex-col bg-[var(--color-paper)] font-sans text-[var(--color-ink)]">
      <header className="sticky top-0 z-30 border-b border-[var(--color-line)] bg-[var(--color-surface)]/95 backdrop-blur-md">
        <nav className="mx-auto flex max-w-6xl items-center border-b border-[var(--color-line)]/80 pr-16">
          <NavLink to="/closet" className={tabClass}>
            Items
          </NavLink>
          <NavLink to="/outfits" className={tabClass}>
            Outfits
          </NavLink>
          <NavLink to="/calendar" className={tabClass}>
            Calendar
          </NavLink>
          <NavLink to="/stats" className={tabClass}>
            Stats
          </NavLink>
          <div className="absolute right-3 top-1/2 -translate-y-1/2" ref={settingsRef}>
            <button
              type="button"
              aria-label="Open settings"
              onClick={() => setSettingsOpen((open) => !open)}
              className="rounded-full p-2 text-[var(--color-muted)] hover:bg-[var(--color-hover)] hover:text-[var(--color-ink)]"
            >
              <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="1.8">
                <path d="M9.7 4.2a1 1 0 0 1 1-.7h2.6a1 1 0 0 1 1 .7l.4 1.2a1 1 0 0 0 1 .7h1.2a1 1 0 0 1 .9.5l1.3 2.2a1 1 0 0 1-.1 1l-.9 1a1 1 0 0 0 0 1.3l.9 1a1 1 0 0 1 .1 1l-1.3 2.2a1 1 0 0 1-.9.5h-1.2a1 1 0 0 0-1 .7l-.4 1.2a1 1 0 0 1-1 .7h-2.6a1 1 0 0 1-1-.7l-.4-1.2a1 1 0 0 0-1-.7H7.2a1 1 0 0 1-.9-.5L5 15.1a1 1 0 0 1 .1-1l.9-1a1 1 0 0 0 0-1.3l-.9-1a1 1 0 0 1-.1-1l1.3-2.2a1 1 0 0 1 .9-.5h1.2a1 1 0 0 0 1-.7l.4-1.2Z" />
                <circle cx="12" cy="12" r="2.8" />
              </svg>
            </button>
            {settingsOpen ? (
              <div className="absolute right-0 top-12 w-56 rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-3 shadow-xl">
                <label className="flex cursor-pointer items-center justify-between gap-3 rounded-xl px-3 py-2 text-sm text-[var(--color-ink)] hover:bg-[var(--color-hover)]">
                  <span>Dark mode</span>
                  <input
                    type="checkbox"
                    checked={darkMode}
                    onChange={(event) => setDarkMode(event.target.checked)}
                    className="h-4 w-4 accent-[var(--color-sage)]"
                  />
                </label>
                <button
                  type="button"
                  onClick={() => {
                    logout()
                    navigate('/login', { replace: true })
                  }}
                  className="mt-2 w-full rounded-xl px-3 py-2 text-left text-sm text-[var(--color-ink)] hover:bg-[var(--color-hover)]"
                >
                  Sign out
                </button>
              </div>
            ) : null}
          </div>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
        {children ?? <Outlet />}
      </main>
    </div>
  )
}
