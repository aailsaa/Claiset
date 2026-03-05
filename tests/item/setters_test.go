package tests

import (
	cb "OnlineCloset/src/closetBuilder"
	testPkg "OnlineCloset/tests"
	"reflect"
	"testing"
	"time"
)

func TestSetName(t *testing.T) {
	DEFAULT_NAME := "test1"
	tests := []struct {
		new, expected string
	}{
		{"shirt1", "shirt1"},
		{"shirt2   ", "shirt2"},
		{"\nshirt3", "shirt3"},
		{"", DEFAULT_NAME},
		{"  ", DEFAULT_NAME},
		{DEFAULT_NAME, DEFAULT_NAME},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem(DEFAULT_NAME, []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0)
		currItem.SetName(test.new)
		if currItem.GetName() != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Logf("\nInput: '%s'\nExpected: '%s'\nActual: '%s'", test.new, test.expected, currItem.GetName())
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("\nInput: '%s'\nExpected/actual: '%s'", test.new, currItem.GetName())
			}
		}
	}
}

func TestSetColors(t *testing.T) {
	DEFAULTCOLORS := []cb.Color{cb.RED}
	tests := []struct {
		new, expected []cb.Color
	}{
		// tests that should set colors
		{[]cb.Color{cb.BLUE}, []cb.Color{cb.BLUE}},
		{[]cb.Color{cb.RED, cb.BLUE}, []cb.Color{cb.RED, cb.BLUE}},
		// tests that shouldn't set colors
		{[]cb.Color{}, DEFAULTCOLORS},
		{[]cb.Color{cb.COLORERROR}, DEFAULTCOLORS},
		{[]cb.Color{cb.GREEN, cb.COLORERROR}, DEFAULTCOLORS},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", DEFAULTCOLORS, cb.TOP, cb.BLOUSE, 0)
		currItem.SetColors(test.new)
		if !reflect.DeepEqual(currItem.GetColors(), test.expected) {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nincorrect colors:\nExpected colors: %v\nActual colors: %v",
					idx, cb.StringColors(test.expected), cb.StringColors(currItem.GetColors()))
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nExpected/actual colors: %v", idx, cb.StringColors(test.expected))
			}
		}
	}
}

func TestSetCategories(t *testing.T) {
	DEFAULTCAT := cb.TOP
	DEFAULTSUBCAT := cb.BLOUSE
	tests := []struct {
		newCat, expectedCat       cb.Category
		newSubcat, expectedSubcat cb.Subcategory
	}{
		{cb.BOTTOMS, cb.BOTTOMS, cb.CAPRIS, cb.CAPRIS},
		{cb.SHOES, cb.SHOES, cb.SNEAKERS, cb.SNEAKERS},
		{cb.CATEGORYERROR, DEFAULTCAT, cb.Subcategory(999), DEFAULTSUBCAT},
		{cb.BOTTOMS, DEFAULTCAT, cb.SWEATER, DEFAULTSUBCAT},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", []cb.Color{cb.RED}, DEFAULTCAT, DEFAULTSUBCAT, 0)
		currItem.SetCategories(test.newCat, test.newSubcat)
		if currItem.GetCategory() != test.expectedCat || currItem.GetSubcategory() != test.expectedSubcat {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nincorrect category/subcategory:\nExpected category: %s\nActual: %s\nExpected subcategory: %d\nActual: %d",
					idx, test.expectedCat.String(), currItem.GetCategory().String(), test.expectedSubcat, currItem.GetSubcategory())
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status: Expected/actual category: %s\nExpected/actual subcategory: %d",
					idx, currItem.GetCategory().String(), currItem.GetSubcategory())
			}
		}
	}
}

func TestSetSubcategory(t *testing.T) {
	DEFAULTSUBCAT := cb.BLOUSE
	tests := []struct {
		new, expected cb.Subcategory
	}{
		{cb.SWEATER, cb.SWEATER},
		{cb.CARDIGAN, cb.CARDIGAN},
		{cb.OTHERTOP, cb.OTHERTOP},
		{cb.SNEAKERS, DEFAULTSUBCAT},
		{cb.Subcategory(999), DEFAULTSUBCAT},
		{cb.SUBCATEGORYERROR, DEFAULTSUBCAT},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", []cb.Color{cb.RED}, cb.TOP, DEFAULTSUBCAT, 0)
		currItem.SetSubcategory(test.new)
		if currItem.GetSubcategory() != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nExpected subcategory: %d\nActual: %d", idx, test.expected, currItem.GetSubcategory())
			}
			continue
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status:\nExpected/actual subcategory: %d", idx, currItem.GetSubcategory())
			}
		}
	}
}

func TestSetID(t *testing.T) {
	DEFAULTID := 0
	tests := []struct {
		new, expected int
	}{
		{1, 1},
		{999, 999},
		{-1, DEFAULTID},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, DEFAULTID)
		currItem.SetID(test.new)
		if currItem.GetID() != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nExpected ID: %d\nActual: %d", idx, test.expected, currItem.GetID())
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status:\nExpected/actual ID: %d", idx, currItem.GetID())
			}
		}
	}
}

func TestSetDate(t *testing.T) {
	DEFAULTDATE := cb.EMPTYDATE
	tests := []struct {
		new, expected time.Time
	}{
		{time.Date(2024, time.June, 1, 0, 0, 0, 0, time.UTC), time.Date(2024, time.June, 1, 0, 0, 0, 0, time.UTC)},
		{time.Date(2023, time.December, 25, 0, 0, 0, 0, time.UTC), time.Date(2023, time.December, 25, 0, 0, 0, 0, time.UTC)},
		{time.Date(2027, time.December, 31, 0, 0, 0, 0, time.UTC), DEFAULTDATE},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0)
		currItem.SetDate(test.new)
		if !currItem.GetDate().Equal(test.expected) {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nExpected date: %s\nActual: %s", idx, test.expected.String(), currItem.GetDate().String())
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status:\nExpected/actual date: %s", idx, currItem.GetDate().String())
			}
		}
	}
}

func TestSetPrice(t *testing.T) {
	DEFAULTPRICE := float32(0)
	tests := []struct {
		new, expected float32
	}{
		{19.99, 19.99},
		{6, 6},
		{-5.50, DEFAULTPRICE},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0)
		currItem.SetPrice(test.new)
		if currItem.GetPrice() != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nExpected price: %.2f\nActual: %.2f", idx, test.expected, currItem.GetPrice())
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status:\nExpected/actual price: %.2f", idx, currItem.GetPrice())
			}
		}
	}
}

func TestSetWears(t *testing.T) {
	DEFAULTWEARS := 0
	tests := []struct {
		new, expected int
	}{
		{5, 5},
		{100, 100},
		{-3, DEFAULTWEARS},
		{36526, DEFAULTWEARS},
	}

	for idx, test := range tests {
		currItem := cb.CreateItem("test", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0)
		currItem.SetWears(test.new)
		if currItem.GetWears() != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nExpected wears: %d\nActual: %d", idx, test.expected, currItem.GetWears())
			}
		} else {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status:\nExpected/actual wears: %d", idx, currItem.GetWears())
			}
		}
	}
}
