package tests

import (
	cb "OnlineCloset/src/closet"
	testPkg "OnlineCloset/tests"
	"testing"
)

// outfitsByItems_test tests accessors and mutators for the "OutfitsByItems" field in LocalRelationships.

// accessor tests include:
//
//	* TestGetOutfitsByItem:   Relationship.GetOutfitsByItem
//	* TestHasItemInOBI:       Relationship.HasItemInOBI
//	* TestHasOutfitInOBI:     Relationship.HasOutfitInOBI
//
// mutator tests include:
//
//	* TestAddOutfitByItem:    Relationship.AddOutfitByItem
//	* TestRemoveOutfitByItem: Relationship.RemoveOutfitByItem
//	* TestRemoveItemOBI:      Relationship.RemoveItemOBI

func TestGetOutfitsByItem(t *testing.T) {
	self := createTestItem(0)
	other := createTestItem(1)
	extra := createTestItem(2)
	out := cb.CreateOutfit("coord", []cb.LocalItem{self, other, extra}, 42)

	testIR := cb.CreateRelationships(self.GetID())
	testIR.AddOutfitByItem(&out)

	tests := []struct {
		queryID         int
		expectNil       bool
		expectOutfitKey bool
	}{
		{other.GetID(), false, true},
		{extra.GetID(), false, true},
		{self.GetID(), true, false},
		{999, true, false},
	}

	for idx, test := range tests {
		got := testIR.GetOutfitsByItem(test.queryID)
		errd := false
		if test.expectNil {
			if got != nil {
				t.Errorf(testPkg.TestMessage(idx, false))
				if *testPkg.ExtraVerbose {
					t.Errorf("case %d: expected nil map for item %d", idx, test.queryID)
				}
				errd = true
			}
		} else {
			if got == nil {
				t.Errorf(testPkg.TestMessage(idx, false))
				if *testPkg.ExtraVerbose {
					t.Errorf("case %d: expected non-nil map for item %d", idx, test.queryID)
				}
				errd = true
			} else if test.expectOutfitKey && got[out.GetID()] == nil {
				t.Errorf(testPkg.TestMessage(idx, false))
				if *testPkg.ExtraVerbose {
					t.Errorf("case %d: missing outfit id %d under item %d", idx, out.GetID(), test.queryID)
				}
				errd = true
			}
		}
		if errd {
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}
}

func TestHasItemInOBI(t *testing.T) {
	self := createTestItem(0)
	other := createTestItem(1)
	extra := createTestItem(2)
	out := cb.CreateOutfit("coord", []cb.LocalItem{self, other, extra}, 7)

	testIR := cb.CreateRelationships(self.GetID())
	testIR.AddOutfitByItem(&out)

	tests := []struct {
		otherID  int
		expected bool
	}{
		{other.GetID(), true},
		{extra.GetID(), true},
		{self.GetID(), false},
		{999, false},
	}

	for idx, test := range tests {
		result := testIR.HasItemInOBI(test.otherID)
		if result != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("expected HasItemInOBI(%d) == %t, got %t", test.otherID, test.expected, result)
			}
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}
}

func TestHasOutfitInOBI(t *testing.T) {
	self := createTestItem(0)
	co1 := createTestItem(1)
	co2 := createTestItem(2)
	outA := cb.CreateOutfit("lookA", []cb.LocalItem{self, co1, co2}, 100)
	outB := cb.CreateOutfit("lookB", []cb.LocalItem{self, co1, createTestItem(3)}, 200)

	testIR := cb.CreateRelationships(self.GetID())
	testIR.AddOutfitByItem(&outA)

	tests := []struct {
		otherID  int
		outfit   *cb.LocalOutfit
		expected bool
	}{
		{co1.GetID(), &outA, true},
		{co2.GetID(), &outA, true},
		{self.GetID(), &outA, false},
		{999, &outA, false},
		{co1.GetID(), &outB, false},
		{co2.GetID(), &outB, false},
	}

	for idx, test := range tests {
		result := testIR.HasOutfitInOBI(test.otherID, test.outfit)
		if result != test.expected {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("expected HasOutfitInOBI(%d, outfit id %d) == %t, got %t",
					test.otherID, test.outfit.GetID(), test.expected, result)
			}
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}
}

func TestAddOutfitByItem(t *testing.T) {
	SELFITEM := createTestItem(0)
	REUSEITEM := createTestItem(1)
	i2 := createTestItem(2)
	i3 := createTestItem(3)
	i4 := createTestItem(4)
	i5 := createTestItem(5)
	i6 := createTestItem(6)
	errOut := cb.CreateErrorOutfit()
	emptyOut := cb.CreateEmptyOutfit()

	tests := []struct {
		inputOutfit cb.LocalOutfit
		checkItemID int
		expectedAdd bool
	}{
		{cb.CreateOutfit("test0", []cb.LocalItem{SELFITEM, REUSEITEM, i2}, 0), REUSEITEM.GetID(), true},
		{cb.CreateOutfit("test0", []cb.LocalItem{SELFITEM, REUSEITEM, i2}, 0), i2.GetID(), true},

		{cb.CreateOutfit("test1", []cb.LocalItem{SELFITEM, i3, i4}, 1), i3.GetID(), true},
		{cb.CreateOutfit("test1", []cb.LocalItem{SELFITEM, i3, i4}, 1), i4.GetID(), true},

		{cb.CreateOutfit("test2", []cb.LocalItem{SELFITEM, REUSEITEM, i5}, 2), REUSEITEM.GetID(), true},
		{cb.CreateOutfit("test2", []cb.LocalItem{SELFITEM, REUSEITEM, i5}, 2), i5.GetID(), true},

		{cb.CreateOutfit("test3", []cb.LocalItem{REUSEITEM, i6}, 3), REUSEITEM.GetID(), false},
		{cb.CreateOutfit("test3", []cb.LocalItem{REUSEITEM, i6}, 3), i6.GetID(), false},

		{errOut, REUSEITEM.GetID(), false},
		{emptyOut, REUSEITEM.GetID(), false},
	}

	for idx, test := range tests {
		testIR := cb.CreateRelationships(SELFITEM.GetID())
		testIR.AddOutfitByItem(&test.inputOutfit)

		got := testIR.HasOutfitInOBI(test.checkItemID, &test.inputOutfit)
		if got != test.expectedAdd {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d: HasOutfitInOBI(%d) == %t, want %t\n%s",
					idx, test.checkItemID, got, test.expectedAdd, testIR.String())
			}
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}
}

func TestRemoveOutfitByItem(t *testing.T) {
	self := createTestItem(0)
	co1 := createTestItem(1)
	co2 := createTestItem(2)
	out := cb.CreateOutfit("toRemove", []cb.LocalItem{self, co1, co2}, 50)

	testIR := cb.CreateRelationships(self.GetID())
	testIR.AddOutfitByItem(&out)
	testIR.RemoveOutfitByItem(&out)

	tests := []struct {
		otherID            int
		expectHasOutfit    bool
		expectHasItemInOBI bool
	}{
		{co1.GetID(), false, false},
		{co2.GetID(), false, false},
	}

	for idx, test := range tests {
		errd := false
		if testIR.HasOutfitInOBI(test.otherID, &out) != test.expectHasOutfit {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d: HasOutfitInOBI(%d) want %t", idx, test.otherID, test.expectHasOutfit)
			}
			errd = true
		}
		if testIR.HasItemInOBI(test.otherID) != test.expectHasItemInOBI {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d: HasItemInOBI(%d) want %t", idx, test.otherID, test.expectHasItemInOBI)
			}
			errd = true
		}
		if errd {
			if *testPkg.ExtraVerbose {
				t.Logf("\n%s", testIR.String())
			}
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}
}

func TestRemoveItemOBI(t *testing.T) {
	self := createTestItem(0)
	co := createTestItem(1)
	out := cb.CreateOutfit("solo", []cb.LocalItem{self, co}, 33)

	testIR := cb.CreateRelationships(self.GetID())
	testIR.AddOutfitByItem(&out)
	testIR.RemoveItemOBI(co)

	tests := []struct {
		queryID            int
		expectedHasItemOBI bool
		expectedGetNil     bool
	}{
		{co.GetID(), false, true},
	}

	for idx, test := range tests {
		errd := false
		if testIR.HasItemInOBI(test.queryID) != test.expectedHasItemOBI {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d: HasItemInOBI(%d) want %t", idx, test.queryID, test.expectedHasItemOBI)
			}
			errd = true
		}
		got := testIR.GetOutfitsByItem(test.queryID)
		gotNil := got == nil
		if gotNil != test.expectedGetNil {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d: GetOutfitsByItem(%d) nil=%t want nil=%t", idx, test.queryID, gotNil, test.expectedGetNil)
			}
			errd = true
		}
		if errd {
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}
}

func createTestItem(id int) cb.LocalItem {
	switch id {
	case 0:
		return *cb.CreateItem("item0", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0)
	case 1:
		return *cb.CreateItem("item1", []cb.Color{cb.ORANGE}, cb.BOTTOMS, cb.SHORTS, 1)
	case 2:
		return *cb.CreateItem("item2", []cb.Color{cb.YELLOW}, cb.SHOES, cb.SNEAKERS, 2)
	case 3:
		return *cb.CreateItem("item3", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, 3)
	case 4:
		return *cb.CreateItem("item4", []cb.Color{cb.BLACK}, cb.SHOES, cb.HEELS, 4)
	case 5:
		return *cb.CreateItem("item5", []cb.Color{cb.WHITE}, cb.SHOES, cb.BOOTS, 5)
	case 6:
		return *cb.CreateItem("item6", []cb.Color{cb.BROWN}, cb.ACCESSORY, cb.BELT, 6)
	default:
		return cb.CreateEmptyItem()
	}
}
