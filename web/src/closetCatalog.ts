/**
 * Mirrors enums in src/closet (color.go, category.go, subcategory.go).
 * Keep in sync when Go definitions change.
 */

export const CLOSET_COLORS = [
  { id: 'RED', swatch: '#c62828' },
  { id: 'ORANGE', swatch: '#ef6c00' },
  { id: 'YELLOW', swatch: '#f9a825' },
  { id: 'GREEN', swatch: '#2e7d32' },
  { id: 'BLUE', swatch: '#1565c0' },
  { id: 'PURPLE', swatch: '#6a1b9a' },
  { id: 'PINK', swatch: '#c2185b' },
  { id: 'BROWN', swatch: '#5d4037' },
  { id: 'BLACK', swatch: '#1a1a1a' },
  { id: 'WHITE', swatch: '#f5f5f5' },
  { id: 'GREY', swatch: '#78909c' },
  { id: 'SILVER', swatch: 'linear-gradient(135deg,#eceff1 0%,#b0bec5 45%,#eceff1 100%)' },
  { id: 'GOLD', swatch: 'linear-gradient(135deg,#ffe082 0%,#ffb300 50%,#ff8f00 100%)' },
  {
    id: 'MULTICOLOR',
    swatch:
      'conic-gradient(from 0deg, #e53935, #fb8c00, #fdd835, #43a047, #1e88e5, #8e24aa, #e53935)',
  },
] as const

export type ClosetColorId = (typeof CLOSET_COLORS)[number]['id']

const colorById = Object.fromEntries(CLOSET_COLORS.map((c) => [c.id, c])) as Record<
  ClosetColorId,
  (typeof CLOSET_COLORS)[number]
>

export function closetColorSwatch(id: string): string {
  const c = colorById[id as ClosetColorId]
  return c?.swatch ?? '#9e9e9e'
}

const LABEL_OVERRIDES: Record<string, string> = {
  ONEPIECE: 'One piece',
  OUTERWEAR: 'Outerwear',
  MULTICOLOR: 'Multicolor',
  LONGSLEEVE: 'Long sleeve',
  SLEEVELESS: 'Sleeveless',
  SWEATPANTS: 'Sweatpants',
  TEESHIRT: 'Tee shirt',
  TANKTOP: 'Tank top',
  HAIRACCESSORY: 'Hair accessory',
  SUNGLASSES: 'Sunglasses',
  FANNYPACK: 'Fanny pack',
  SHOULDERBAG: 'Shoulder bag',
  SUBOTHER: 'Other',
  OTHERTOP: 'Other top',
  OTHERBOTTOMS: 'Other bottoms',
  OTHEROUTERWEAR: 'Other outerwear',
  OTHERONEPIECE: 'Other one-piece',
  OTHERSHOES: 'Other shoes',
  OTHERACCESSORY: 'Other accessory',
  OTHERJEWELRY: 'Other jewelry',
  OTHERBAG: 'Other bag',
}

function titleCaseWord(w: string) {
  return w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : ''
}

function splitAllCapsId(id: string): string[] {
  // Split "SHOULDERBAG" -> ["SHOULDER","BAG"] using a tiny word bank for multi-word ids.
  const WORDS = [
    'SHOULDER',
    'SLEEVE',
    'LONG',
    'TEE',
    'TANK',
    'SUN',
    'GLASSES',
    'HAIR',
    'FANNY',
    'PACK',
    'ONE',
    'PIECE',
    'OUTER',
    'WEAR',
  ]
  const wordSet = new Set(WORDS)
  const parts: string[] = []
  let i = 0
  while (i < id.length) {
    let matched = ''
    for (const w of WORDS) {
      if (id.startsWith(w, i) && w.length > matched.length) matched = w
    }
    if (matched) {
      parts.push(matched)
      i += matched.length
      continue
    }
    // fallback: consume until next known word boundary or end
    let j = i + 1
    while (j <= id.length) {
      const rest = id.slice(j)
      const canMatchRest = [...wordSet].some((w) => rest.startsWith(w))
      if (canMatchRest) break
      j++
    }
    parts.push(id.slice(i, Math.min(j, id.length)))
    i = Math.min(j, id.length)
  }
  return parts.filter(Boolean)
}

export function closetLabel(id: string): string {
  const raw = String(id ?? '').trim().toUpperCase()
  if (!raw) return ''
  const override = LABEL_OVERRIDES[raw]
  if (override) return override
  const parts = splitAllCapsId(raw)
  return parts.map((p) => titleCaseWord(p)).join(' ')
}

export const CLOSET_CATEGORIES = [
  'TOP',
  'BOTTOMS',
  'OUTERWEAR',
  'ONEPIECE',
  'SHOES',
  'ACCESSORY',
  'JEWELRY',
  'BAG',
  'OTHER',
] as const

export type ClosetCategoryId = (typeof CLOSET_CATEGORIES)[number]

/** Subcategories per category — same ranges as closet.GetSubFromCat */
export const SUBCATEGORIES_BY_CATEGORY: Record<ClosetCategoryId, readonly string[]> = {
  TOP: [
    'BLOUSE',
    'CARDIGAN',
    'HOODIE',
    'LONGSLEEVE',
    'SLEEVELESS',
    'SWEATER',
    'SWEATSHIRT',
    'TANKTOP',
    'TEESHIRT',
    'TUNIC',
    'OTHERTOP',
  ],
  BOTTOMS: [
    'CAPRIS',
    'DENIM',
    'LEGGINGS',
    'SHORTS',
    'SKIRT',
    'SWEATPANTS',
    'TIGHTS',
    'TROUSERS',
    'OTHERBOTTOMS',
  ],
  OUTERWEAR: [
    'BLAZER',
    'FLEECE',
    'JACKET',
    'PARKA',
    'PUFFER',
    'VEST',
    'WINDBREAKER',
    'OTHEROUTERWEAR',
  ],
  ONEPIECE: ['BODYSUIT', 'DRESS', 'JUMPSUIT', 'OVERALLS', 'ROMPER', 'OTHERONEPIECE'],
  SHOES: [
    'BOOTS',
    'CLOGS',
    'FLATS',
    'HEELS',
    'LOAFERS',
    'PLATFORMS',
    'SANDALS',
    'SNEAKERS',
    'WEDGES',
    'OTHERSHOES',
  ],
  ACCESSORY: [
    'BELT',
    'GLOVES',
    'HAIRACCESSORY',
    'HAT',
    'SCARF',
    'SUNGLASSES',
    'TIE',
    'OTHERACCESSORY',
  ],
  JEWELRY: ['BRACELET', 'EARRING', 'NECKLACE', 'RING', 'WATCH', 'OTHERJEWELRY'],
  BAG: ['BACKPACK', 'CLUTCH', 'FANNYPACK', 'HANDBAG', 'SATCHEL', 'SHOULDERBAG', 'TOTE', 'OTHERBAG'],
  OTHER: ['SUBOTHER'],
}
