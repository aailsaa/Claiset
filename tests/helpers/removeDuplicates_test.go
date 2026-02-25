package tests

import (
	cb "OnlineCloset/src/closetBuilder"
	helpers "OnlineCloset/src/helpers"
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
		result := helpers.RemoveDuplicates(test.input)
		if reflect.DeepEqual(result, test.expected) {
			t.Logf("\nTest %d PASSED", idx)
		} else {
			t.Logf("\nTest %d FAILED:\nExpected: %v\nActual: %v", idx, cb.StringColors(test.expected), cb.StringColors(result))
		}
	}
}
