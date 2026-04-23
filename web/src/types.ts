export type Item = {
  id: number
  name: string
  colors: string[]
  category: string
  subcategory: string
  price: number
  wears: number
  itemDate?: string | null
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
}

export type Assignment = {
  id: number
  outfitId: number
  day: string
  notes?: string
}
