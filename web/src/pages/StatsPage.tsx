import { useCallback, useEffect, useMemo, useState } from 'react'
import { fetchItems, fetchOutfits } from '../api'
import { computeClosetStats } from '../closetStats'
import { closetColorSwatch, closetLabel } from '../closetCatalog'
import type { ClosetStats, Item } from '../types'

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
  barColor,
}: {
  label: string
  sub?: string
  pct: number
  valueRight: string
  barColor?: string
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
          className="h-full rounded-full transition-[width] duration-300"
          style={{ width: `${w}%`, background: barColor ?? 'var(--color-sage)' }}
        />
      </div>
    </div>
  )
}

type ChartDatum = {
  label: string
  value: number
  valueRight: string
  sub?: string
  color?: string
}

function solidChartColor(label: string): string {
  const key = String(label).trim().toUpperCase()
  const map: Record<string, string> = {
    RED: '#c62828',
    ORANGE: '#ef6c00',
    YELLOW: '#f9a825',
    GREEN: '#2e7d32',
    BLUE: '#1565c0',
    PURPLE: '#6a1b9a',
    PINK: '#c2185b',
    BROWN: '#5d4037',
    BLACK: '#1a1a1a',
    WHITE: '#d9d9d9',
    GREY: '#78909c',
    SILVER: '#b0bec5',
    GOLD: '#ffb300',
    MULTICOLOR: '#9a1530',
    UNSPECIFIED: '#9e9e9e',
  }
  return map[key] ?? '#9a1530'
}

function PieChart({
  rows,
}: {
  rows: ChartDatum[]
}) {
  const positive = rows.filter((r) => r.value > 0)
  const total = positive.reduce((sum, r) => sum + r.value, 0)
  const palette = ['#f6b3c1', '#f08aa5', '#d9688d', '#ba4e79', '#9a1530', '#fbd1db', '#f39ab1', '#cf5b84']
  if (!total) return <p className="text-sm text-[var(--color-muted)]">No data yet.</p>

  let cursor = 0
  const slices = positive.map((row, idx) => {
    const size = (row.value / total) * 100
    const start = cursor
    cursor += size
    return {
      ...row,
      color: row.color ?? palette[idx % palette.length],
      start,
      end: cursor,
    }
  })

  const gradient = slices
    .map((s) => `${s.color} ${s.start.toFixed(2)}% ${s.end.toFixed(2)}%`)
    .join(', ')

  return (
    <div className="space-y-3">
      <div className="mx-auto h-44 w-44 rounded-full ring-1 ring-[var(--color-line)]" style={{ background: `conic-gradient(${gradient})` }} />
      <div className="space-y-2">
        {slices.map((s) => (
          <div key={s.label} className="flex items-center justify-between gap-2 rounded-xl border border-[var(--color-line)] bg-[var(--color-surface)] px-3 py-2 text-sm">
            <div className="flex items-center gap-2">
              <span className="h-3 w-3 rounded-full" style={{ background: s.color }} />
              <span className="font-medium text-[var(--color-ink)]">{s.label}</span>
              {s.sub ? <span className="text-xs text-[var(--color-muted)]">{s.sub}</span> : null}
            </div>
            <span className="text-[var(--color-muted)]">{s.valueRight}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

export function StatsPage() {
  const [stats, setStats] = useState<ClosetStats | null>(null)
  const [items, setItems] = useState<Item[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [chartMode, setChartMode] = useState<'bar' | 'pie'>(() => {
    try {
      const raw = window.localStorage.getItem('stats:view:chartMode')
      return raw === 'pie' ? 'pie' : 'bar'
    } catch {
      return 'bar'
    }
  })

  useEffect(() => {
    try {
      window.localStorage.setItem('stats:view:chartMode', chartMode)
    } catch {
      // ignore
    }
  }, [chartMode])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [items, outfits] = await Promise.all([fetchItems(), fetchOutfits()])
      setItems(items)
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

  const activeItems = useMemo(() => items.filter((it) => !it.archived), [items])

  const priceBreakdown = useMemo(() => {
    const secondHand = activeItems.filter((it) => it.extra?.secondHand === true || String(it.extra?.secondHand).toLowerCase() === 'true')
    const newItems = activeItems.filter((it) => !(it.extra?.secondHand === true || String(it.extra?.secondHand).toLowerCase() === 'true'))

    const secondHandSpend = secondHand.reduce((acc, it) => acc + (Number(it.price) || 0), 0)
    const newSpend = newItems.reduce((acc, it) => acc + (Number(it.price) || 0), 0)

    return {
      avgSecondHandPrice: secondHand.length ? secondHandSpend / secondHand.length : 0,
      avgNewPrice: newItems.length ? newSpend / newItems.length : 0,
    }
  }, [activeItems])

  const wearBreakdown = useMemo(() => {
    const byType = new Map<string, number>()
    const byColor = new Map<string, number>()

    for (const it of activeItems) {
      const wears = Math.max(0, Number(it.wears) || 0)
      const type = String(it.category || '').trim() || 'Uncategorized'
      byType.set(type, (byType.get(type) || 0) + wears)

      const cols = (it.colors ?? []).map((c) => String(c).trim()).filter(Boolean)
      if (cols.length === 0) {
        byColor.set('Unspecified', (byColor.get('Unspecified') || 0) + wears)
      } else {
        const w = wears / cols.length
        for (const c of cols) {
          const key = c.toUpperCase()
          byColor.set(key, (byColor.get(key) || 0) + w)
        }
      }
    }

    const topTypes = [...byType.entries()]
      .map(([label, wears]) => ({ label, wears }))
      .sort((a, b) => b.wears - a.wears)
      .slice(0, 6)

    const topColors = [...byColor.entries()]
      .map(([label, wears]) => ({ label, wears }))
      .sort((a, b) => b.wears - a.wears)
      .slice(0, 6)

    const sortedByWears = [...activeItems]
      .sort((a, b) => (Number(b.wears) || 0) - (Number(a.wears) || 0))
      .map((it) => ({
        id: it.id,
        name: it.name || `Item #${it.id}`,
        wears: Number(it.wears) || 0,
        category: String(it.category || '').trim() || 'Uncategorized',
      }))

    const mostWorn = sortedByWears.slice(0, 5)
    const leastWorn = [...sortedByWears].reverse().slice(0, 5)
    const totalWears = sortedByWears.reduce((acc, it) => acc + it.wears, 0)
    const avgPerItem = sortedByWears.length ? totalWears / sortedByWears.length : 0
    const unwornCount = sortedByWears.filter((it) => it.wears === 0).length

    return { topTypes, topColors, mostWorn, leastWorn, totalWears, avgPerItem, unwornCount }
  }, [activeItems])

  const avgCostPerWearPerItem = useMemo(() => {
    const perItem = activeItems
      .map((it) => {
        const wears = Math.max(0, Number(it.wears) || 0)
        const price = Math.max(0, Number(it.price) || 0)
        if (wears <= 0) return null
        return price / wears
      })
      .filter((v): v is number => v != null)
    if (perItem.length === 0) return null
    return perItem.reduce((sum, v) => sum + v, 0) / perItem.length
  }, [activeItems])

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-3xl">Statistics</h1>
        <div className="inline-flex items-center gap-1 rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-1">
          <button
            type="button"
            onClick={() => setChartMode('bar')}
            className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold transition ${
              chartMode === 'bar' ? 'bg-[var(--color-paper)] text-[var(--color-ink)] shadow-sm' : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
            }`}
            title="Bar charts"
            aria-label="Show bar charts"
          >
            <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M4 20V10" />
              <path d="M10 20V4" />
              <path d="M16 20v-7" />
              <path d="M22 20v-3" />
            </svg>
          </button>
          <button
            type="button"
            onClick={() => setChartMode('pie')}
            className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold transition ${
              chartMode === 'pie' ? 'bg-[var(--color-paper)] text-[var(--color-ink)] shadow-sm' : 'text-[var(--color-muted)] hover:text-[var(--color-ink)]'
            }`}
            title="Pie charts"
            aria-label="Show pie charts"
          >
            <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 3v9h9" />
              <path d="M20.49 13A9 9 0 1 1 11 3.06" />
            </svg>
          </button>
        </div>
      </div>

      {error ? (
        <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>
      ) : null}

      {loading ? <p className="text-sm text-[var(--color-muted)]">Loading statistics…</p> : null}

      {!loading && stats ? (
        <>
          <section className="rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Items breakdown</h2>
            <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Items</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{stats.totalItems}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Outfits</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{stats.outfitCount}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Second hand</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">
                  {stats.totalItems ? `${stats.secondHandPct.toFixed(0)}%` : '—'}
                </p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Avg item age</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">
                  {stats.avgItemAgeYears != null ? `${stats.avgItemAgeYears.toFixed(1)}y` : '—'}
                </p>
              </div>
            </div>

            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Closet by type</h3>
                <div className="mt-3 space-y-3">
                  {stats.byCategory.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      stats.byCategory.map((row) => (
                        <BarRow
                          key={row.category}
                          label={closetLabel(row.category)}
                          sub={`${row.count} items`}
                          pct={row.pct}
                          valueRight={`${row.pct.toFixed(0)}%`}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={stats.byCategory.map((row) => ({
                          label: closetLabel(row.category),
                          sub: `${row.count} items`,
                          value: row.pct,
                          valueRight: `${row.pct.toFixed(0)}%`,
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Closet by color</h3>
                <div className="mt-3 space-y-3">
                  {stats.byColor.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      stats.byColor.slice(0, 8).map((row) => (
                        <BarRow
                          key={row.color}
                          label={closetLabel(row.color)}
                          pct={row.pct}
                          valueRight={`${row.pct.toFixed(0)}%`}
                          barColor={solidChartColor(row.color)}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={stats.byColor.slice(0, 8).map((row) => ({
                          label: closetLabel(row.color),
                          value: row.pct,
                          valueRight: `${row.pct.toFixed(0)}%`,
                          color: solidChartColor(row.color),
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Items by purchase year</h3>
                <div className="mt-3 space-y-3">
                  {stats.byPurchaseYear.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      stats.byPurchaseYear.map((row) => (
                        <BarRow
                          key={row.year === null ? 'undated' : row.year}
                          label={row.year === null ? 'Unspecified' : String(row.year)}
                          sub={`${row.count} items`}
                          pct={(row.count / maxLongevityCount) * 100}
                          valueRight={`${row.pct.toFixed(0)}%`}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={stats.byPurchaseYear.map((row) => ({
                          label: row.year === null ? 'Unspecified' : String(row.year),
                          sub: `${row.count} items`,
                          value: row.count,
                          valueRight: `${row.pct.toFixed(0)}%`,
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
            </div>
          </section>

          <section className="rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Price breakdown</h2>
            <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Total spent</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{usd(stats.totalSpend)}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Avg item price</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{usdCents(stats.avgItemPrice)}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Avg second-hand price</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{usdCents(priceBreakdown.avgSecondHandPrice)}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Avg new price</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{usdCents(priceBreakdown.avgNewPrice)}</p>
              </div>
            </div>

            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Money spent by type</h3>
                <div className="mt-3 space-y-3">
                  {stats.byCategory.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      stats.byCategory.map((row) => (
                        <BarRow
                          key={`spend-${row.category}`}
                          label={closetLabel(row.category)}
                          sub={`${row.count} items`}
                          pct={(row.spend / maxCatSpend) * 100}
                          valueRight={usd(row.spend)}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={stats.byCategory.map((row) => ({
                          label: closetLabel(row.category),
                          sub: `${row.count} items`,
                          value: row.spend,
                          valueRight: usd(row.spend),
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Average cost by type</h3>
                <div className="mt-3 space-y-3">
                  {stats.byCategory.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items yet.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      stats.byCategory.map((row) => (
                        <BarRow
                          key={`avg-${row.category}`}
                          label={closetLabel(row.category)}
                          sub={`${row.count} items`}
                          pct={(row.avgPrice / maxAvgByType) * 100}
                          valueRight={usdCents(row.avgPrice)}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={stats.byCategory.map((row) => ({
                          label: closetLabel(row.category),
                          sub: `${row.count} items`,
                          value: row.avgPrice,
                          valueRight: usdCents(row.avgPrice),
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
            </div>

            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Spending by month</h3>
                <div className="mt-3 space-y-3">
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
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Spending by year</h3>
                <div className="mt-3 space-y-3">
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
              </div>
            </div>
          </section>

          <section className="rounded-3xl border border-[var(--color-line)] bg-[var(--color-surface)] p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[var(--color-sage)]">Wears breakdown</h2>

            <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Total wears</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{wearBreakdown.totalWears}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Avg cost / wear</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">
                  {avgCostPerWearPerItem == null ? '—' : usdCents(avgCostPerWearPerItem)}
                </p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Avg wears / item</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{wearBreakdown.avgPerItem.toFixed(1)}</p>
              </div>
              <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-surface)] p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Unworn items</p>
                <p className="mt-1 text-xl font-semibold tabular-nums text-[var(--color-ink)]">{wearBreakdown.unwornCount}</p>
              </div>
            </div>

            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Most worn item types</h3>
                <div className="mt-3 space-y-3">
                  {wearBreakdown.topTypes.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items in this time frame.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      wearBreakdown.topTypes.map((row, i) => (
                        <BarRow
                          key={`wtype-${row.label}`}
                          label={closetLabel(row.label)}
                          sub={`#${i + 1}`}
                          pct={wearBreakdown.topTypes[0].wears > 0 ? (row.wears / wearBreakdown.topTypes[0].wears) * 100 : 0}
                          valueRight={`${row.wears.toFixed(0)} wears`}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={wearBreakdown.topTypes.map((row, i) => ({
                          label: closetLabel(row.label),
                          sub: `#${i + 1}`,
                          value: row.wears,
                          valueRight: `${row.wears.toFixed(0)} wears`,
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Most worn colors</h3>
                <div className="mt-3 space-y-3">
                  {wearBreakdown.topColors.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items in this time frame.</p>
                  ) : (
                    chartMode === 'bar' ? (
                      wearBreakdown.topColors.map((row, i) => (
                        <BarRow
                          key={`wcolor-${row.label}`}
                          label={closetLabel(row.label)}
                          sub={`#${i + 1}`}
                          pct={wearBreakdown.topColors[0].wears > 0 ? (row.wears / wearBreakdown.topColors[0].wears) * 100 : 0}
                          valueRight={`${row.wears.toFixed(1)} wears`}
                          barColor={solidChartColor(row.label)}
                        />
                      ))
                    ) : (
                      <PieChart
                        rows={wearBreakdown.topColors.map((row, i) => ({
                          label: closetLabel(row.label),
                          sub: `#${i + 1}`,
                          value: row.wears,
                          valueRight: `${row.wears.toFixed(1)} wears`,
                          color: solidChartColor(row.label),
                        }))}
                      />
                    )
                  )}
                </div>
              </div>
            </div>

            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Most worn items</h3>
                <div className="mt-3 space-y-2">
                  {wearBreakdown.mostWorn.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items in this time frame.</p>
                  ) : (
                    wearBreakdown.mostWorn.map((it) => (
                      <div key={`most-${it.id}`} className="flex items-center justify-between rounded-xl border border-[var(--color-line)] bg-[var(--color-surface)] px-3 py-2 text-sm">
                        <div>
                          <p className="font-medium text-[var(--color-ink)]">{it.name}</p>
                          <p className="text-xs text-[var(--color-muted)]">{closetLabel(it.category)}</p>
                        </div>
                        <span className="tabular-nums text-[var(--color-muted)]">{it.wears}</span>
                      </div>
                    ))
                  )}
                </div>
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[var(--color-ink)]">Least worn items</h3>
                <div className="mt-3 space-y-2">
                  {wearBreakdown.leastWorn.length === 0 ? (
                    <p className="text-sm text-[var(--color-muted)]">No items in this time frame.</p>
                  ) : (
                    wearBreakdown.leastWorn.map((it) => (
                      <div key={`least-${it.id}`} className="flex items-center justify-between rounded-xl border border-[var(--color-line)] bg-[var(--color-surface)] px-3 py-2 text-sm">
                        <div>
                          <p className="font-medium text-[var(--color-ink)]">{it.name}</p>
                          <p className="text-xs text-[var(--color-muted)]">{closetLabel(it.category)}</p>
                        </div>
                        <span className="tabular-nums text-[var(--color-muted)]">{it.wears}</span>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          </section>
        </>
      ) : null}
    </div>
  )
}
