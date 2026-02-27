package closetBuilder

// Subcategory represents possible subcategories of each type of clothing

type Subcategory int

// all subcategory types as enum
const (
	// 0-10 category TOP
	BLOUSE     Subcategory = iota //0
	CARDIGAN                      //1
	HOODIE                        //2
	LONGSLEEVE                    //3
	SLEEVELESS                    //4
	SWEATER                       //5
	SWEATSHIRT                    //6
	TANKTOP                       //7
	TEESHIRT                      //8
	TUNIC                         //9
	OTHERTOP                      //10
	// 11-19 category BOTTOMS
	CAPRIS       //11
	DENIM        //12
	LEGGINGS     //13
	SHORTS       //14
	SKIRT        //15
	SWEATPANTS   //16
	TIGHTS       //17
	TROUSERS     //18
	OTHERBOTTOMS //19
	// 20-27 category OUTERWEAR
	BLAZER         //20
	FLEECE         //21
	JACKET         //22
	PARKA          //23
	PUFFER         //24
	VEST           //25
	WINDBREAKER    //26
	OTHEROUTERWEAR //27
	// 28-33 category ONEPIECE
	BODYSUIT      //28
	DRESS         //29
	JUMPSUIT      //30
	OVERALLS      //31
	ROMPER        //32
	OTHERONEPIECE //33
	// 34-43 category SHOES
	BOOTS      //34
	CLOGS      //35
	FLATS      //36
	HEELS      //37
	LOAFERS    //38
	PLATFORMS  //39
	SANDALS    //40
	SNEAKERS   //41
	WEDGES     //42
	OTHERSHOES //43
	// 44-51 category ACCESSORY
	BELT           //44
	GLOVES         //45
	HAIRACCESSORY  //46
	HAT            //47
	SCARF          //48
	SUNGLASSES     //49
	TIE            //50
	OTHERACCESSORY //51
	// 52-57 category JEWELRY
	BRACELET     //52
	EARRING      //53
	NECKLACE     //54
	RING         //55
	WATCH        //56
	OTHERJEWELRY //57
	// 58-65 category BAG
	BACKPACK    //58
	CLUTCH      //59
	FANNYPACK   //60
	HANDBAG     //61
	SATCHEL     //62
	SHOULDERBAG //63
	TOTE        //64
	OTHERBAG    //65
	// 66 category OTHER
	SUBOTHER //66
	// error category
	SUBCATEGORYERROR //67
)

// consts of limits of each subcategory
// each uses the next as its high limit
const TOPSTART = BLOUSE
const BOTTOMSSTART = CAPRIS
const OUTERWEARSTART = BLAZER
const ONEPIECESTART = BODYSUIT
const SHOESSTART = BOOTS
const ACCESSORYSTART = BELT
const JEWELRYSTART = BRACELET
const BAGSTART = BACKPACK
const OTHERSTART = SUBOTHER

const SUBCATEGORYSTART = TOPSTART
const SUBCATEGORYEND = OTHERSTART

// map to convert enum back to string representation
var SubcategoryNames = map[Subcategory]string{
	BLOUSE:     "BLOUSE",
	CARDIGAN:   "CARDIGAN",
	HOODIE:     "HOODIE",
	LONGSLEEVE: "LONGSLEEVE",
	SLEEVELESS: "SLEEVELESS",
	SWEATER:    "SWEATER",
	SWEATSHIRT: "SWEATSHIRT",
	TANKTOP:    "TANKTOP",
	TEESHIRT:   "TEESHIRT",
	TUNIC:      "TUNIC",
	OTHERTOP:   "OTHERTOP",

	CAPRIS:       "CAPRIS",
	DENIM:        "DENIM",
	LEGGINGS:     "LEGGINGS",
	SHORTS:       "SHORTS",
	SKIRT:        "SKIRT",
	SWEATPANTS:   "SWEATPANTS",
	TIGHTS:       "TIGHTS",
	TROUSERS:     "TROUSERS",
	OTHERBOTTOMS: "OTHERBOTTOMS",

	BLAZER:         "BLAZER",
	FLEECE:         "FLEECE",
	JACKET:         "JACKET",
	PARKA:          "PARKA",
	PUFFER:         "PUFFER",
	VEST:           "VEST",
	WINDBREAKER:    "WINDBREAKER",
	OTHEROUTERWEAR: "OTHEROUTERWEAR",

	BODYSUIT:      "BODYSUIT",
	DRESS:         "DRESS",
	JUMPSUIT:      "JUMPSUIT",
	OVERALLS:      "OVERALLS",
	ROMPER:        "ROMPER",
	OTHERONEPIECE: "OTHERONEPIECE",

	BOOTS:      "BOOTS",
	CLOGS:      "CLOGS",
	FLATS:      "FLATS",
	HEELS:      "HEELS",
	LOAFERS:    "LOAFERS",
	PLATFORMS:  "PLATFORMS",
	SANDALS:    "SANDALS",
	SNEAKERS:   "SNEAKERS",
	WEDGES:     "WEDGES",
	OTHERSHOES: "OTHERSHOES",

	BELT:           "BELT",
	GLOVES:         "GLOVES",
	HAIRACCESSORY:  "HAIRACCESSORY",
	HAT:            "HAT",
	SCARF:          "SCARF",
	SUNGLASSES:     "SUNGLASSES",
	TIE:            "TIE",
	OTHERACCESSORY: "OTHERACCESSORY",

	BRACELET:     "BRACELET",
	EARRING:      "EARRING",
	NECKLACE:     "NECKLACE",
	RING:         "RING",
	WATCH:        "WATCH",
	OTHERJEWELRY: "OTHERJEWELRY",

	BACKPACK:    "BACKPACK",
	CLUTCH:      "CLUTCH",
	FANNYPACK:   "FANNYPACK",
	HANDBAG:     "HANDBAG",
	SATCHEL:     "SATCHEL",
	SHOULDERBAG: "SHOULDERBAG",
	TOTE:        "TOTE",
	OTHERBAG:    "OTHERBAG",

	SUBOTHER:         "SUBOTHER",
	SUBCATEGORYERROR: "SUBCATEGORYERROR",
}

// string function for subcategory
func (s Subcategory) String() string {
	if s < BLOUSE || s > SUBCATEGORYERROR {
		return ""
	}
	return SubcategoryNames[s]
}

// GetAllSubcategories returns a list of all subcategories without distinction
func GetAllSubcategories() []Subcategory {
	return getIdxSubs(BLOUSE, SUBCATEGORYERROR)
}

// getSpecificSubs is a helper that takes in parameters
func getIdxSubs(start, end Subcategory) []Subcategory {
	size := int(end - start)
	rval := make([]Subcategory, size)
	idx := 0
	for i := start; i < end; i++ {
		rval[idx] = i
		idx++
	}
	return rval
}

// GetSubFromCat takes in a category and returns the corresponding subcategories
func GetSubFromCat(c Category) []Subcategory {
	switch c {
	case TOP:
		return getIdxSubs(TOPSTART, BOTTOMSSTART)
	case BOTTOMS:
		return getIdxSubs(BOTTOMSSTART, OUTERWEARSTART)
	case OUTERWEAR:
		return getIdxSubs(OUTERWEARSTART, ONEPIECESTART)
	case ONEPIECE:
		return getIdxSubs(ONEPIECESTART, SHOESSTART)
	case SHOES:
		return getIdxSubs(SHOESSTART, ACCESSORYSTART)
	case ACCESSORY:
		return getIdxSubs(ACCESSORYSTART, JEWELRYSTART)
	case JEWELRY:
		return getIdxSubs(JEWELRYSTART, BAGSTART)
	case BAG:
		return getIdxSubs(BAGSTART, OTHERSTART)
	case OTHER:
		return getIdxSubs(OTHERSTART, OTHERSTART+1)
	default:
		return []Subcategory{SUBCATEGORYERROR}
	}
}

func (s Subcategory) IsValid() bool {
	if s < SUBCATEGORYSTART || s > SUBCATEGORYEND {
		return false
	}
	return true
}

// TODO:
// * weather
// * occasion
