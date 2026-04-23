import { useEffect, useRef, useState } from 'react'
import { closetLabel, CLOSET_COLORS } from '../closetCatalog'

type Props = {
  /** Color ids already chosen; they are omitted from the list */
  omit: ReadonlySet<string>
  onAdd: (colorId: string) => void
  disabled?: boolean
}

export function ClosetColorAddSelect({ omit, onAdd, disabled }: Props) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    function onDocDown(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onDocDown)
    return () => document.removeEventListener('mousedown', onDocDown)
  }, [open])

  const available = CLOSET_COLORS.filter((c) => !omit.has(c.id))

  return (
    <div className="relative mt-1" ref={rootRef}>
      <button
        type="button"
        disabled={disabled || available.length === 0}
        aria-expanded={open}
        aria-haspopup="listbox"
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center justify-between rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-left text-sm text-[var(--color-ink)] outline-none ring-[var(--color-sage)]/30 hover:bg-[var(--color-paper)] focus:ring-2 disabled:cursor-not-allowed disabled:opacity-50"
      >
        <span className="text-[var(--color-muted)]">
          {available.length === 0 ? 'All colors added' : 'Add a color…'}
        </span>
        <span className="text-xs text-[var(--color-muted)]" aria-hidden>
          ▾
        </span>
      </button>
      {open && available.length > 0 ? (
        <ul
          className="absolute z-50 mt-1 max-h-52 w-full overflow-auto rounded-xl border border-[var(--color-line)] bg-white py-1 shadow-lg"
          role="listbox"
          aria-label="Choose a color"
        >
          {available.map((c) => (
            <li key={c.id} role="presentation">
              <button
                type="button"
                role="option"
                className="flex w-full items-center gap-3 px-3 py-2.5 text-left text-sm hover:bg-[var(--color-paper)]"
                onClick={() => {
                  onAdd(c.id)
                  setOpen(false)
                }}
              >
                <span
                  className="h-5 w-5 shrink-0 rounded-md ring-1 ring-black/10"
                  style={{ background: c.swatch }}
                  aria-hidden
                />
                <span className="font-medium tracking-wide text-[var(--color-ink)]">{closetLabel(c.id)}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  )
}
