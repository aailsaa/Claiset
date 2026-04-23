package tests

import (
	cb "OnlineCloset/src/closet"
	util "OnlineCloset/src/util"
	testPkg "OnlineCloset/tests"
	"reflect"
	"testing"
)

func TestRemoveDuplicates(t *testing.T) {

	testColors := []struct {
		input    []cb.Color
		expected []cb.Color
	}{
		{[]cb.Color{cb.RED}, []cb.Color{cb.RED}},

		{[]cb.Color{cb.RED, cb.ORANGE, cb.YELLOW, cb.YELLOW}, []cb.Color{cb.RED, cb.ORANGE, cb.YELLOW}},

		{[]cb.Color{cb.RED, cb.ORANGE, cb.RED}, []cb.Color{cb.RED, cb.ORANGE}},

		{[]cb.Color{}, []cb.Color{}},

		{[]cb.Color{cb.RED, cb.RED, cb.RED, cb.RED, cb.RED}, []cb.Color{cb.RED}},
	}

	for idx, test := range testColors {
		result := util.RemoveDuplicates(test.input)
		if reflect.DeepEqual(result, test.expected) {
			t.Logf(testPkg.TestMessage(idx, true))
			if *testPkg.ExtraVerbose {
				t.Logf("case %d status:\nInput: %v\nExpected/actual: %v", idx, test.input, result)
			}
		} else {
			t.Errorf(testPkg.TestMessage(idx, false))
			if *testPkg.ExtraVerbose {
				t.Errorf("case %d status:\nInput: %v\nExpected: %v\nActual: %v", idx, test.input, test.expected, result)
			}
		}
	}
}
