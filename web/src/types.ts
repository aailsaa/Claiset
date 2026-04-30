export type Item = {
  id: number
  name: string
  colors: string[]
  category: string
  subcategory: string
  price: number
  wears: number
  itemDate?: string | null
  /** When the row was first saved (server-set). */
  createdAt?: string | null
  photoDataUrl?: string | null
  extra?: ItemExtra | null
  archived?: boolean
}

export type ItemExtra = {
  acquisitionMethod?: string
  secondHand?: boolean
  weather?: string[]
  seasons?: string[]
  size?: string
  brand?: string
  condition?: string
  locationPurchased?: string
  notes?: string
}

export type Outfit = {
  id: number
  name: string
  wears: number
  itemIds: number[]
  coverDataUrl?: string | null
  extra?: OutfitExtra | null
  layout?: OutfitLayoutLayer[] | null
  pictures?: OutfitPicture[] | null
}

export type OutfitExtra = {
  weather?: string[]
  seasons?: string[]
  notes?: string
}

export type OutfitLayoutLayer = {
  itemId: number
  x: number // 0..1 relative
  y: number // 0..1 relative
  scale: number
  rotationDeg: number
  z: number
}

export type OutfitPicture = {
  id: string
  dataUrl: string
  takenAt: string
  backgroundRemoved?: boolean
  /** YYYY-MM-DD when added from the calendar (which day this photo is for) */
  wornOnDay?: string
}

export type Assignment = {
  id: number
  outfitId: number
  day: string
  notes?: string
}

export type CategoryStat = {
  category: string
  count: number
  spend: number
  pct: number
  /** Average price among items in this category */
  avgPrice: number
}

export type MonthStat = {
  year: number
  month: number
  period: string
  spend: number
}

export type YearStat = {
  year: number
  spend: number
}

/** Share of closet by color (each item splits evenly across its selected colors). */
export type ColorStat = {
  color: string
  pct: number
}

export type AcquisitionStat = {
  source: string
  count: number
  pct: number
}

/** Item counts by purchase year (`item_date`); `year: null` is undated items. */
export type LongevityYearStat = {
  year: number | null
  count: number
  pct: number
}

export type ClosetStats = {
  totalItems: number
  totalSpend: number
  avgItemPrice: number
  totalWears: number
  avgCostPerWear: number
  secondHandCount: number
  secondHandPct: number
  /** Mean years from each item's purchase date (`itemDate`) through today; null if no dated items. */
  avgItemAgeYears: number | null
  byCategory: CategoryStat[]
  byMonth: MonthStat[]
  byYear: YearStat[]
  byColor: ColorStat[]
  byAcquisition: AcquisitionStat[]
  byPurchaseYear: LongevityYearStat[]
  outfitCount: number
  totalOutfitWears: number
}
