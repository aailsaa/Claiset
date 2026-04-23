import type { ReactNode } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'

const tabClass = ({ isActive }: { isActive: boolean }) =>
  [
    'relative flex-1 px-4 py-3 text-center text-sm font-semibold transition-colors sm:text-base',
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

  return (
    <div className="flex min-h-screen flex-col text-[var(--color-ink)]">
      <header className="sticky top-0 z-20 border-b border-[var(--color-line)] bg-[var(--color-paper)]/95 backdrop-blur-md">
        <nav className="mx-auto flex max-w-6xl items-center border-b border-[var(--color-line)]/80">
          <NavLink to="/closet" className={tabClass}>
            Items
          </NavLink>
          <NavLink to="/outfits" className={tabClass}>
            Outfits
          </NavLink>
          <NavLink to="/calendar" className={tabClass}>
            Calendar
          </NavLink>
          <div className="shrink-0 border-l border-[var(--color-line)] px-2 py-1 sm:px-3">
            <button
              type="button"
              onClick={() => {
                logout()
                navigate('/login', { replace: true })
              }}
              className="rounded-full px-3 py-2 text-xs font-medium text-[var(--color-muted)] hover:bg-white/80 hover:text-[var(--color-ink)] sm:text-sm"
            >
              Sign out
            </button>
          </div>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
        {children ?? <Outlet />}
      </main>
    </div>
  )
}
