import type {
  AcquisitionStat,
  ClosetStats,
  ColorStat,
  Item,
  LongevityYearStat,
  Outfit,
} from './types'

const MS_PER_YEAR = 365.25 * 24 * 60 * 60 * 1000

function isSecondHand(extra: Item['extra']): boolean {
  const sh = extra?.secondHand
  return sh === true || String(sh).toLowerCase() === 'true'
}

/** Purchase calendar in UTC (item dates are stored as `YYYY-MM-DDT00:00:00Z`). */
function itemCalendarUtc(iso: string | null | undefined): { y: number; m: number } | null {
  const s = iso == null ? '' : String(iso).trim()
  if (!s) return null
  const d = new Date(s)
  if (Number.isNaN(d.getTime())) return null
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1 }
}

/** Mean years from purchase date (`itemDate`) to now (longevity). */
function avgItemAgeYears(active: Item[]): number | null {
  const now = Date.now()
  let sum = 0
  let c = 0
  for (const it of active) {
    const d = it.itemDate ? new Date(it.itemDate) : null
    if (!d || Number.isNaN(d.getTime())) continue
    sum += (now - d.getTime()) / MS_PER_YEAR
    c++
  }
  return c > 0 ? sum / c : null
}

/**
 * Aggregates the same item/outfit payloads the closet uses so totals stay in sync with the Items page.
 */
export function computeClosetStats(items: Item[], outfits: Outfit[]): ClosetStats {
  const active = items.filter((it) => !it.archived)
  const n = active.length

  let totalSpend = 0
  let totalWears = 0
  let secondHandCount = 0

  const catMap = new Map<string, { count: number; spend: number }>()
  const monthMap = new Map<string, { y: number; m: number; spend: number }>()
  const yearSpendMap = new Map<number, number>()
  const colorWeights = new Map<string, number>()
  const acquisitionMap = new Map<string, number>()
  const purchaseYearCounts = new Map<number, number>()
  let undatedCount = 0

  for (const it of active) {
    const price = Number(it.price) || 0
    const wears = Number(it.wears) || 0
    totalSpend += price
    totalWears += wears

    if (isSecondHand(it.extra)) secondHandCount++

    const cal = itemCalendarUtc(it.itemDate ?? undefined)
    if (cal) {
      const period = `${cal.y}-${String(cal.m).padStart(2, '0')}`
      const bucket = monthMap.get(period) ?? { y: cal.y, m: cal.m, spend: 0 }
      bucket.spend += price
      monthMap.set(period, bucket)
      yearSpendMap.set(cal.y, (yearSpendMap.get(cal.y) || 0) + price)
      purchaseYearCounts.set(cal.y, (purchaseYearCounts.get(cal.y) || 0) + 1)
    } else {
      undatedCount++
    }

    const rawCat = String(it.category ?? '').trim()
    const label = rawCat === '' ? 'Uncategorized' : rawCat
    const c = catMap.get(label) ?? { count: 0, spend: 0 }
    c.count += 1
    c.spend += price
    catMap.set(label, c)

    const cols = (it.colors ?? []).map((x) => String(x).trim()).filter(Boolean)
    if (cols.length === 0) {
      colorWeights.set('Unspecified', (colorWeights.get('Unspecified') || 0) + 1)
    } else {
      const w = 1 / cols.length
      for (const col of cols) {
        const key = col.toUpperCase()
        colorWeights.set(key, (colorWeights.get(key) || 0) + w)
      }
    }

    const rawAcq = String(it.extra?.acquisitionMethod ?? '').trim()
    const acqLabel = rawAcq === '' ? 'Unspecified' : rawAcq
    acquisitionMap.set(acqLabel, (acquisitionMap.get(acqLabel) || 0) + 1)
  }

  const avgItemPrice = n > 0 ? totalSpend / n : 0
  const secondHandPct = n > 0 ? (100 * secondHandCount) / n : 0
  const avgCostPerWear = totalWears > 0 ? totalSpend / totalWears : 0

  const byCategory = [...catMap.entries()]
    .map(([category, { count, spend }]) => ({
      category,
      count,
      spend,
      pct: n > 0 ? (100 * count) / n : 0,
      avgPrice: count > 0 ? spend / count : 0,
    }))
    .sort((a, b) => b.count - a.count)

  const byMonth = [...monthMap.values()]
    .map((v) => ({
      year: v.y,
      month: v.m,
      period: `${v.y}-${String(v.m).padStart(2, '0')}`,
      spend: v.spend,
    }))
    .sort((a, b) => a.year - b.year || a.month - b.month)

  const byYear = [...yearSpendMap.entries()]
    .map(([year, spend]) => ({ year, spend }))
    .sort((a, b) => a.year - b.year)

  const byColor: ColorStat[] = [...colorWeights.entries()]
    .map(([color, weight]) => ({
      color,
      pct: n > 0 ? (100 * weight) / n : 0,
    }))
    .sort((a, b) => b.pct - a.pct)

  const byAcquisition: AcquisitionStat[] = [...acquisitionMap.entries()]
    .map(([source, count]) => ({
      source,
      count,
      pct: n > 0 ? (100 * count) / n : 0,
    }))
    .sort((a, b) => b.count - a.count)

  const byPurchaseYear: LongevityYearStat[] = [...purchaseYearCounts.entries()]
    .map(([year, count]) => ({
      year,
      count,
      pct: n > 0 ? (100 * count) / n : 0,
    }))
    .sort((a, b) => a.year - b.year)
  if (undatedCount > 0) {
    byPurchaseYear.push({
      year: null,
      count: undatedCount,
      pct: n > 0 ? (100 * undatedCount) / n : 0,
    })
  }

  let totalOutfitWears = 0
  for (const o of outfits) {
    totalOutfitWears += Number(o.wears) || 0
  }

  return {
    totalItems: n,
    totalSpend,
    avgItemPrice,
    totalWears,
    avgCostPerWear,
    secondHandCount,
    secondHandPct,
    avgItemAgeYears: avgItemAgeYears(active),
    byCategory,
    byMonth,
    byYear,
    byColor,
    byAcquisition,
    byPurchaseYear,
    outfitCount: outfits.length,
    totalOutfitWears,
  }
}
