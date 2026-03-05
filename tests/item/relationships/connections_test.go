package tests

import (
	cb "OnlineCloset/src/closetBuilder"
	testPkg "OnlineCloset/tests"
	"testing"
)

// connections_test tests all accessors and mutators for the "connections" field in the Relationships item.

// accessor tests include:
//		* TestGetConnection:	Relationship.GetConnection
//		* TestHasConnection: 	Relationship.HasConnection
// mutator tests include:
// 		* TestAddConnection: 	Relationship.AddConnection
//		* TestSetConnection: 	Relationship.SetConnection
//		* TestRemoveConnection: Relationship.RemoveConnection

// these tests are all conducted on an empty Relationships object, independent of the Item object.

// TestGetConnection: test Relationship's GetConnection method
func TestGetConnection(t *testing.T) {
	SELFID := 5
	tests := []struct {
		inputItem        cb.Item
		inputStrength    float32
		expectedStrength float32
	}{
		// items in the connections map that should return their given strength
		{*cb.CreateItem("test0", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0), 5, 5},

		{*cb.CreateItem("test1", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, 1), 1, 1},

		{*cb.CreateItem("test2", []cb.Color{cb.GREEN}, cb.OUTERWEAR, cb.JACKET, 2), -2, -2},

		// items not in the connections map that shouldn't return strength
		{*cb.CreateItem("test3", []cb.Color{cb.ORANGE}, cb.TOP, cb.BLOUSE, 3), cb.ERRCONNECTION, cb.ERRCONNECTION},
		{*cb.CreateItem("test4", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.SCARF, 4), cb.ERRCONNECTION, cb.ERRCONNECTION},
		// self item: shouldn't return connection
		{*cb.CreateItem("test5", []cb.Color{cb.BLACK, cb.WHITE}, cb.OUTERWEAR, cb.JACKET, 5), cb.ERRCONNECTION, cb.ERRCONNECTION},
		// err item: shouldn't return connection
		{cb.CreateEmptyItem(), cb.ERRCONNECTION, cb.ERRCONNECTION},
	}

	testIR := cb.CreateRelationships(SELFID)
	for i := range 3 {
		testIR.AddConnection(tests[i].inputItem, tests[i].inputStrength)
	}

	for idx, test := range tests {
		currC := testIR.GetConnection(test.inputItem.GetID())
		if currC != test.expectedStrength {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nexpected strength: %f\nactual strength: %f",
					idx, test.expectedStrength, currC)
			}
			continue
		}

		t.Logf(testPkg.TestMessage(idx, true))
	}
}

// TestHasConnection: test Relationship's HasConnection method
func TestHasConnection(t *testing.T) {
	SELFID := 5
	tests := []struct {
		inputItem          cb.Item
		expectedConnection bool
	}{
		// items in the connection map
		{*cb.CreateItem("test0", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0), true},
		{*cb.CreateItem("test1", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, 1), true},
		{*cb.CreateItem("test2", []cb.Color{cb.GREEN}, cb.OUTERWEAR, cb.JACKET, 2), true},
		//items not in the connection map
		{*cb.CreateItem("test3", []cb.Color{cb.ORANGE}, cb.TOP, cb.BLOUSE, 3), false},
		{*cb.CreateItem("test4", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.SCARF, 4), false},
		// self item: shoudln't return connection
		{*cb.CreateItem("test5", []cb.Color{cb.BLACK, cb.WHITE}, cb.OUTERWEAR, cb.JACKET, SELFID), false},
		// error item: shouldn't return connection
		{cb.CreateEmptyItem(), false},
	}

	testIR := cb.CreateRelationships(SELFID)
	for i := range 3 {
		testIR.AddConnection(tests[i].inputItem, cb.NEUTRALCONNECTION)
	}

	for idx, test := range tests {
		result := testIR.HasConnection(test.inputItem.GetID())
		if result != test.expectedConnection {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("expected connection status for item %d: %t\nactual status: %t",
					test.inputItem.GetID(), test.expectedConnection, result)
			}
			continue
		}
		t.Logf(testPkg.TestMessage(idx, true))
	}

}

// TestAddConnection: tests Relationship's AddConnection method
func TestAddConnection(t *testing.T) {
	SELFID := 5
	tests := []struct {
		inputItem                       cb.Item
		inputStrength, expectedStrength float32
	}{
		// tests that should add a connection
		{*cb.CreateItem("test0", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0), 5, 5},
		{*cb.CreateItem("test1", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, 1), -3, -3},
		{*cb.CreateItem("test2", []cb.Color{cb.GREEN}, cb.OUTERWEAR, cb.JACKET, 2), 4.5, 4.5},

		// tests that should fail to add a connection
		{*cb.CreateItem("test3", []cb.Color{cb.YELLOW}, cb.ONEPIECE, cb.DRESS, 3), -12, cb.ERRCONNECTION},
		{*cb.CreateItem("test4", []cb.Color{cb.BLACK}, cb.SHOES, cb.SNEAKERS, 4), 15, cb.ERRCONNECTION},
		{*cb.CreateItem("test5", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.HAT, SELFID), 0, cb.ERRCONNECTION},
		{cb.CreateEmptyItem(), 9, cb.ERRCONNECTION},
	}

	testIR := cb.CreateRelationships(SELFID)
	for idx, test := range tests {
		testIR.AddConnection(test.inputItem, test.inputStrength)

		resultStrength := testIR.GetConnection(test.inputItem.GetID())
		otherResultStrength := test.inputItem.GetConnection(SELFID)
		errd := false

		if resultStrength != test.expectedStrength {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nincorrect result strength:\nExpected connection strength: %f\n"+
					"Actual connection strength: %f", idx, test.expectedStrength, resultStrength)
			}
			errd = true
		}

		if otherResultStrength != test.expectedStrength {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nincorrect strength in other item\nExpected connection strength in other item: %f\n"+
					"Actual connection strength in other item: %f", idx, test.expectedStrength, otherResultStrength)
			}
			errd = true
		}

		if errd && *testPkg.ExtraVerbose {
			t.Errorf("\nCurrent state of ItemRelationships:\n%s", testIR.String())
		}

		if errd {
			return
		}

		t.Logf(testPkg.TestMessage(idx, true))

		if *testPkg.ExtraVerbose {
			t.Logf("\nCurrent state of ItemRelationships:\n%s", testIR.String())
		}
	}
}

// TestSetConnection: tests Relationship's SetConnection method
func TestSetConnection(t *testing.T) {
	DEFAULTCONNECTION := cb.NEUTRALCONNECTION
	SELFID := 10
	tests := []struct {
		inputItem                       cb.Item
		inputStrength, expectedStrength float32
	}{
		// tests that should set a connection
		{*cb.CreateItem("test0", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0), 5, 5},
		{*cb.CreateItem("test1", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, 1), -3, -3},
		{*cb.CreateItem("test2", []cb.Color{cb.GREEN}, cb.OUTERWEAR, cb.JACKET, 2), 4.5, 4.5},

		// tests that should fail to set a connection:
		// invalid input strength & existing connection:
		{*cb.CreateItem("test3", []cb.Color{cb.YELLOW}, cb.ONEPIECE, cb.DRESS, 3), -12, DEFAULTCONNECTION},
		{*cb.CreateItem("test4", []cb.Color{cb.BLACK}, cb.SHOES, cb.SNEAKERS, 4), 15, DEFAULTCONNECTION},
		{*cb.CreateItem("test5", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.HAT, 5), cb.ERRCONNECTION, DEFAULTCONNECTION},
		// invalid input strength & no connection:
		{*cb.CreateItem("test6", []cb.Color{cb.YELLOW}, cb.ONEPIECE, cb.DRESS, 6), -12, cb.ERRCONNECTION},
		{*cb.CreateItem("test7", []cb.Color{cb.BLACK}, cb.SHOES, cb.SNEAKERS, 7), 15, cb.ERRCONNECTION},
		// valid input strength & no connection:
		{*cb.CreateItem("test8", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.HAT, 8), 0, cb.ERRCONNECTION},
		{*cb.CreateItem("test9", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.HAT, 9), 5, cb.ERRCONNECTION},
		// duplicating with self
		{*cb.CreateItem("test10", []cb.Color{cb.WHITE}, cb.ACCESSORY, cb.HAT, SELFID), 5, cb.ERRCONNECTION},
		// invalid item input
		{cb.CreateEmptyItem(), 3, cb.ERRCONNECTION},
	}
	testIR := cb.CreateRelationships(SELFID)
	for i := range 6 {
		currTest := tests[i]
		testIR.AddConnection(currTest.inputItem, DEFAULTCONNECTION)

	}
	if *testPkg.ExtraVerbose {
		t.Logf("\nInitial state of ItemRelationships:\n%s", testIR.String())
	}

	for idx, test := range tests {
		testIR.SetConnection(test.inputItem, test.inputStrength)

		resultStrength := testIR.GetConnection(test.inputItem.GetID())
		otherResultStrength := test.inputItem.GetConnection(SELFID)
		errd := false

		if resultStrength != test.expectedStrength {
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:incorrect result strength:\nExpected connection strength: %f\n"+
					"Actual connection strength: %f", idx, test.expectedStrength, resultStrength)
			}
			errd = true
		}

		if otherResultStrength != test.expectedStrength {
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nincorrect other item result strength\nExpected connection strength in other item: %f\n"+
					"Actual connection strength in other item: %f", idx, test.expectedStrength, otherResultStrength)
			}
			errd = true
		}

		if errd {
			t.Errorf(testPkg.TestMessage(idx, false))
		}

		if errd && *testPkg.ExtraVerbose {
			t.Errorf("\nCurrent state of ItemRelationships:\n%s", testIR.String())
			return
		}

		t.Logf(testPkg.TestMessage(idx, true))
		if *testPkg.ExtraVerbose {
			t.Logf("\nCurrent state of ItemRelationships:\n%s", testIR.String())
		}
	}
}

// TestRemoveConnection: tests Relationship's RemoveConnection method
func TestRemoveConnection(t *testing.T) {
	SELFID := 6
	tests := []struct {
		removeItem cb.Item
	}{
		// items that should be removed because they're in the connections map
		{*cb.CreateItem("test0", []cb.Color{cb.RED}, cb.TOP, cb.BLOUSE, 0)},
		{*cb.CreateItem("test1", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, 1)},
		{*cb.CreateItem("test2", []cb.Color{cb.GREEN}, cb.OUTERWEAR, cb.JACKET, 2)},
		// items that shouldn't be removed because they're not in the map
		{*cb.CreateItem("test3", []cb.Color{cb.ORANGE}, cb.TOP, cb.BLOUSE, 3)},
		{*cb.CreateItem("test4", []cb.Color{cb.YELLOW}, cb.BOTTOMS, cb.DENIM, 4)},
		{*cb.CreateItem("test5", []cb.Color{cb.BLACK, cb.WHITE}, cb.OUTERWEAR, cb.JACKET, 5)},
		// shouldn't remove: self item
		{*cb.CreateItem("test6", []cb.Color{cb.BLUE}, cb.BOTTOMS, cb.DENIM, SELFID)},
		// shouldn't remove: error item
		{cb.CreateEmptyItem()},
	}

	testIR := cb.CreateRelationships(SELFID)
	for i := range 3 {
		testIR.AddConnection(tests[i].removeItem, cb.NEUTRALCONNECTION)
	}

	for idx, test := range tests {
		testIR.RemoveConnection(test.removeItem)
		errd := false
		if testIR.HasConnection(test.removeItem.GetID()) {
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nconnections map still contains item %d", idx, test.removeItem.GetID())
			}
			errd = true
		}
		if test.removeItem.HasConnection(SELFID) {
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nitem %d still has connection to main test item", idx, test.removeItem.GetID())
			}
			errd = true
		}

		if !errd {
			t.Logf(testPkg.TestMessage(idx, true))
		} else {
			t.Errorf(testPkg.TestMessage(idx, false))
		}

		if *testPkg.ExtraVerbose {
			t.Logf("\nCurrent state of ItemRelationships:\n%s\nCurrent item relationships:\n%s", testIR.String(), test.removeItem.String())
		}
	}
}
