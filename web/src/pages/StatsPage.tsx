import { useCallback, useEffect, useMemo, useState } from 'react'
import { fetchItems, fetchOutfits } from '../api'
import { computeClosetStats } from '../closetStats'
import { closetLabel } from '../closetCatalog'
import type { ClosetStats } from '../types'

function usd(n: number) {
  return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(n)
}

function usdCents(n: number) {
  return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
}

function monthLabel(period: string) {
  const [y, m] = period.split('-').map((x) => parseInt(x, 10))
  if (!Number.isFinite(y) || !Number.isFinite(m)) return period
  return new Date(y, m - 1, 1).toLocaleString(undefined, { month: 'short', year: 'numeric' })
}

function BarRow({
  label,
  sub,
  pct,
  valueRight,
}: {
  label: string
  sub?: string
  pct: number
  valueRight: string
}) {
  const w = Math.min(100, Math.max(0, pct))
  return (
    <div className="space-y-1">
      <div className="flex items-baseline justify-between gap-2 text-sm">
        <div>
          <span className="font-medium text-[var(--color-ink)]">{label}</span>
          {sub ? <span className="ml-2 text-xs text-[var(--color-muted)]">{sub}</span> : null}
        </div>
        <span className="shrink-0 tabular-nums text-[var(--color-muted)]">{valueRight}</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-[var(--color-surface)] ring-1 ring-[var(--color-line)]">
        <div
          className="h-full rounded-full bg-[var(--color-sage)] transition-[width] duration-300"
          style={{ width: `${w}%` }}
        />
      </div>
    </div>
  )
}

export function StatsPage() {
  const [stats, setStats] = useState<ClosetStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [items, outfits] = await Promise.all([fetchItems(), fetchOutfits()])
      setStats(computeClosetStats(items, outfits))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load statistics')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const maxMonth = useMemo(() => {
    if (!stats?.byMonth.length) return 1
    let m = 0
    for (const row of stats.byMonth) m = Math.max(m, row.spend)
    return m || 1
  }, [stats])

  const maxYear = useMemo(() => {
    if (!stats?.byYear.length) return 1
    let m = 0
    for (const row of stats.byYear) m = Math.max(m, row.spend)
    return m || 1
  }, [stats])

  const maxCatSpend = useMemo(() => {
    if (!stats?.byCategory.length) return 1
    let m = 0
    for (const row of stats.byCategory) m = Math.max(m, row.spend)
    return m || 1
  }, [stats])

  const maxAvgByType = useMemo(() => {
    if (!stats?.byCategory.length) return 1
    let m = 0
    for (const row of stats.byCategory) m = Math.max(m, row.avgPrice)
    return m || 1
  }, [stats])

  const maxLongevityCount = useMemo(() => {
    if (!stats?.byPurchaseYear.length) return 1
    let m = 0
    for (const row of stats.byPurchaseYear) m = Math.max(m, row.count)
    return m || 1
  }, [stats])

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-3xl">Statistics</h1>
      </div>

      {error ? (
        <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>
      ) : null}

      {loading ? <p className="text-sm text-[var(--color-muted)]">Loading statistics…</p> : null}

      {!loading && stats ? (
        <>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div className="rounded-3xl border border-[var(--color-line)] bg-white p-5 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Total spent</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-[var(--color-ink)]">{usd(stats.totalSpend)}</p>
              <p className="mt-1 text-xs text-[var(--color-muted)]">{stats.totalItems} items · avg {usdCents(stats.avgItemPrice)}</p>
            </div>
            <div className="rounded-3xl border border-[var(--color-line)] bg-white p-5 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Second hand</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-[var(--color-ink)]">
                {stats.totalItems ? `${stats.secondHandPct.toFixed(0)}%` : '—'}
              </p>
              <p className="mt-1 text-xs text-[var(--color-muted)]">
                {stats.secondHandCount} of {stats.totalItems} items
              </p>
            </div>
            <div className="rounded-3xl border border-[var(--color-line)] bg-white p-5 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Total wears</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-[var(--color-ink)]">{stats.totalWears}</p>
              <p className="mt-1 text-xs text-[var(--color-muted)]">
                Avg cost / wear {stats.totalWears ? usdCents(stats.avgCostPerWear) : '—'}
              </p>
            </div>
            <div className="rounded-3xl border border-[var(--color-line)] bg-white p-5 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Outfits</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-[var(--color-ink)]">{stats.outfitCount}</p>
              <p className="mt-1 text-xs text-[var(--color-muted)]">{stats.totalOutfitWears} logged outfit wears</p>
            </div>
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">Closet by type</h2>
              <div className="mt-5 space-y-4">
                {stats.byCategory.length === 0 ? (
                  <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                ) : (
                  stats.byCategory.map((row) => (
                    <BarRow
                      key={row.category}
                      label={closetLabel(row.category)}
                      sub={`${row.count} items`}
                      pct={row.pct}
                      valueRight={usd(row.spend)}
                    />
                  ))
                )}
              </div>
            </section>

            <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">Money spent by type</h2>
              <div className="mt-5 space-y-4">
                {stats.byCategory.length === 0 ? (
                  <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                ) : (
                  stats.byCategory.map((row) => (
                    <BarRow
                      key={`spend-${row.category}`}
                      label={closetLabel(row.category)}
                      sub={`${row.count} items`}
                      pct={(row.spend / maxCatSpend) * 100}
                      valueRight={usd(row.spend)}
                    />
                  ))
                )}
              </div>
            </section>
          </div>

          <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Average cost by type</h2>
            <div className="mt-5 space-y-4">
              {stats.byCategory.length === 0 ? (
                <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
              ) : (
                stats.byCategory.map((row) => (
                  <BarRow
                    key={`avg-${row.category}`}
                    label={closetLabel(row.category)}
                    sub={`${row.count} items`}
                    pct={(row.avgPrice / maxAvgByType) * 100}
                    valueRight={usdCents(row.avgPrice)}
                  />
                ))
              )}
            </div>
          </section>

          <div className="grid gap-6 lg:grid-cols-2">
            <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">Closet by color</h2>
              <div className="mt-5 space-y-4">
                {stats.byColor.length === 0 ? (
                  <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                ) : (
                  stats.byColor.map((row) => (
                    <BarRow
                      key={row.color}
                      label={closetLabel(row.color)}
                      pct={row.pct}
                      valueRight={`${row.pct.toFixed(0)}%`}
                    />
                  ))
                )}
              </div>
            </section>

            <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
              <h2 className="text-lg font-semibold text-[var(--color-sage)]">By acquisition</h2>
              <div className="mt-5 space-y-4">
                {stats.byAcquisition.length === 0 ? (
                  <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                ) : (
                  stats.byAcquisition.map((row) => (
                    <BarRow
                      key={row.source}
                      label={row.source}
                      sub={`${row.count} items`}
                      pct={row.pct}
                      valueRight={`${row.pct.toFixed(0)}%`}
                    />
                  ))
                )}
              </div>
            </section>
          </div>

          <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Longevity</h2>
            {stats.avgItemAgeYears != null ? (
              <p className="mt-2 text-sm text-[var(--color-ink)]">
                Average years since purchase (purchase date through today):{' '}
                <span className="font-semibold tabular-nums">{stats.avgItemAgeYears.toFixed(1)}</span>
              </p>
            ) : (
              <p className="mt-2 text-sm text-[var(--color-muted)]">Add purchase dates on items to see average longevity.</p>
            )}
            <div className="mt-5 space-y-3">
              {stats.byPurchaseYear.length === 0 ? (
                <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
              ) : (
                stats.byPurchaseYear.map((row) => (
                  <BarRow
                    key={row.year === null ? 'undated' : row.year}
                    label={row.year === null ? 'No purchase date' : String(row.year)}
                    sub={`${row.count} items`}
                    pct={(row.count / maxLongevityCount) * 100}
                    valueRight={`${row.pct.toFixed(0)}%`}
                  />
                ))
              )}
            </div>
          </section>

          <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Spending by month</h2>
            <div className="mt-5 space-y-3">
              {stats.byMonth.length === 0 ? (
                <p className="text-sm text-[var(--color-muted)]">No dated purchases yet.</p>
              ) : (
                stats.byMonth.map((row) => (
                  <BarRow
                    key={row.period}
                    label={monthLabel(row.period)}
                    pct={(row.spend / maxMonth) * 100}
                    valueRight={usd(row.spend)}
                  />
                ))
              )}
            </div>
          </section>

          <section className="rounded-3xl border border-[var(--color-line)] bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Spending by year</h2>
            <div className="mt-5 space-y-3">
              {stats.byYear.length === 0 ? (
                <p className="text-sm text-[var(--color-muted)]">No dated purchases yet.</p>
              ) : (
                stats.byYear.map((row) => (
                  <BarRow
                    key={row.year}
                    label={String(row.year)}
                    pct={(row.spend / maxYear) * 100}
                    valueRight={usd(row.spend)}
                  />
                ))
              )}
            </div>
          </section>
        </>
      ) : null}
    </div>
  )
}
