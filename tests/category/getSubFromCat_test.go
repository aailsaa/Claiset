package tests

import (
	cb "OnlineCloset/src/closetBuilder"
	testPkg "OnlineCloset/tests"
	"reflect"
	"testing"
)

func TestGetSubFromCat(t *testing.T) {
	tests := []struct {
		input    cb.Category
		expected []cb.Subcategory
	}{
		{cb.TOP, []cb.Subcategory{cb.BLOUSE, cb.CARDIGAN, cb.HOODIE, cb.LONGSLEEVE, cb.SLEEVELESS,
			cb.SWEATER, cb.SWEATSHIRT, cb.TANKTOP, cb.TEESHIRT, cb.TUNIC, cb.OTHERTOP}},

		{cb.BOTTOMS, []cb.Subcategory{cb.CAPRIS, cb.DENIM, cb.LEGGINGS, cb.SHORTS, cb.SKIRT,
			cb.SWEATPANTS, cb.TIGHTS, cb.TROUSERS, cb.OTHERBOTTOMS}},

		{cb.OUTERWEAR, []cb.Subcategory{cb.BLAZER, cb.FLEECE, cb.JACKET, cb.PARKA, cb.PUFFER,
			cb.VEST, cb.WINDBREAKER, cb.OTHEROUTERWEAR}},

		{cb.ONEPIECE, []cb.Subcategory{cb.BODYSUIT, cb.DRESS, cb.JUMPSUIT, cb.OVERALLS, cb.ROMPER,
			cb.OTHERONEPIECE}},

		{cb.SHOES, []cb.Subcategory{cb.BOOTS, cb.CLOGS, cb.FLATS, cb.HEELS, cb.LOAFERS, cb.PLATFORMS,
			cb.SANDALS, cb.SNEAKERS, cb.WEDGES, cb.OTHERSHOES}},

		{cb.ACCESSORY, []cb.Subcategory{cb.BELT, cb.GLOVES, cb.HAIRACCESSORY, cb.HAT, cb.SCARF,
			cb.SUNGLASSES, cb.TIE, cb.OTHERACCESSORY}},

		{cb.JEWELRY, []cb.Subcategory{cb.BRACELET, cb.EARRING, cb.NECKLACE, cb.RING, cb.WATCH,
			cb.OTHERJEWELRY}},

		{cb.BAG, []cb.Subcategory{cb.BACKPACK, cb.CLUTCH, cb.FANNYPACK, cb.HANDBAG, cb.SATCHEL,
			cb.SHOULDERBAG, cb.TOTE, cb.OTHERBAG}},

		{cb.OTHER, []cb.Subcategory{cb.SUBOTHER}},
	}

	for idx, test := range tests {
		result := cb.GetSubFromCat(test.input)
		if reflect.DeepEqual(result, test.expected) {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d results:\nInput: %s\nExpected: %v\nActual: %v",
					idx, test.input.String(), test.expected, result)
			}
		} else {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d results:\nInput: %s\nExpected: %v\nActual: %v",
					idx, test.input.String(), test.expected, result)
			}
		}
	}
}
