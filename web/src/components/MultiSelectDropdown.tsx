import { useEffect, useMemo, useRef, useState } from 'react'

export type MultiSelectOption = {
  id: string
  label: string
  swatch?: string
}

type Props = {
  label: string
  options: MultiSelectOption[]
  selected: string[]
  setSelected: (next: string[]) => void
  placeholder?: string
}

export function MultiSelectDropdown({ label, options, selected, setSelected, placeholder }: Props) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    function onDocDown(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDocDown)
    return () => document.removeEventListener('mousedown', onDocDown)
  }, [open])

  const selectedSet = useMemo(() => new Set(selected), [selected])

  return (
    <div className="relative" ref={rootRef}>
      <div className="text-xs font-medium text-[var(--color-muted)]">{label}</div>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="mt-2 flex w-full items-center justify-between rounded-2xl border border-[var(--color-line)] bg-white px-4 py-3 text-left text-sm font-semibold text-[var(--color-ink)] shadow-sm hover:bg-[var(--color-paper)]"
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <span className={selected.length ? 'text-[var(--color-ink)]' : 'text-[var(--color-muted)]'}>
          {selected.length ? `${selected.length} selected` : (placeholder ?? 'Any')}
        </span>
        <span className="text-xs text-[var(--color-muted)]" aria-hidden>
          ▾
        </span>
      </button>

      {open ? (
        <div className="absolute z-50 mt-2 w-full overflow-hidden rounded-2xl border border-[var(--color-line)] bg-white shadow-xl">
          <div className="max-h-64 overflow-auto p-2">
            {options.map((opt) => {
              const on = selectedSet.has(opt.id)
              return (
                <button
                  key={opt.id}
                  type="button"
                  className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-left text-sm hover:bg-[var(--color-paper)]"
                  role="option"
                  aria-selected={on}
                  onClick={() => {
                    setSelected(on ? selected.filter((x) => x !== opt.id) : [...selected, opt.id])
                  }}
                >
                  <span
                    className={`flex h-5 w-5 items-center justify-center rounded-md border ${
                      on ? 'border-[var(--color-sage)] bg-[var(--color-sage)] text-white' : 'border-[var(--color-line)] bg-white text-transparent'
                    }`}
                    aria-hidden
                  >
                    ✓
                  </span>
                  {opt.swatch ? (
                    <span className="h-4 w-4 shrink-0 rounded-sm ring-1 ring-black/10" style={{ background: opt.swatch }} aria-hidden />
                  ) : null}
                  <span className="flex-1 truncate text-[var(--color-ink)]">{opt.label}</span>
                </button>
              )
            })}
          </div>
          <div className="flex gap-2 border-t border-[var(--color-line)] p-2">
            <button
              type="button"
              onClick={() => setSelected([])}
              className="flex-1 rounded-xl border border-[var(--color-line)] bg-white px-3 py-2 text-sm font-semibold text-[var(--color-muted)] hover:bg-[var(--color-paper)]"
            >
              Clear
            </button>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="flex-1 rounded-xl bg-[var(--color-clay)] px-3 py-2 text-sm font-semibold text-white shadow-sm"
            >
              Done
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}

