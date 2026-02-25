package tests

import (
	cb "OnlineCloset/src/closetBuilder"
	"reflect"
	"testing"
)

// tests that all items are being added
func TestAddItem(t *testing.T) {
	tests := []struct {
		inputName        string
		inputColors      []cb.Color
		inputCategory    cb.Category
		inputSubcategory cb.Subcategory
		expectedSize     int
	}{
		{"test1", []cb.Color{cb.RED, cb.GREEN}, cb.TOP, cb.BLOUSE, 1},
		{"test2", []cb.Color{cb.ORANGE}, cb.BOTTOMS, cb.CAPRIS, 2},
		{"test3", []cb.Color{cb.YELLOW}, cb.SHOES, cb.SNEAKERS, 3},
	}

	testCloset := cb.CreateCloset()
	currentSize := 0
	for idx, test := range tests {
		testCloset.AddItem(test.inputName, test.inputColors, test.inputCategory, test.inputSubcategory)
		if testCloset.GetSize() <= currentSize {
			t.Errorf("\nTest case %d FAILED:\nexpected size: %d\nactual size: %d", idx, test.expectedSize, testCloset.GetSize())
		} else if testCloset.GetSize() != testCloset.GetTotalItems() {
			t.Errorf("\nTest case %d FAILED: inaccurate total item counter:\ncounter: %d\nactual size: %d", idx, testCloset.GetTotalItems(), testCloset.GetSize())
		} else {
			t.Logf("\nTest case %d PASSED", idx)
		}
		//t.Logf("\nCurrent closet status:\n%s", testCloset.String())
		currentSize += 1
	}
}

// tests that all items are being added with integrity
func TestAddIntegrity(t *testing.T) {
	tests := []struct {
		inputName        string
		inputColors      []cb.Color
		inputCategory    cb.Category
		inputSubcategory cb.Subcategory
		expectedSize     int
	}{
		{"test1", []cb.Color{cb.RED, cb.GREEN}, cb.TOP, cb.BLOUSE, 1},
		{"test2", []cb.Color{cb.ORANGE}, cb.BOTTOMS, cb.CAPRIS, 2},
		{"test3", []cb.Color{cb.YELLOW}, cb.SHOES, cb.SNEAKERS, 3},
	}

	//persistent vars for testing
	testCloset := cb.CreateCloset()
	currentSize := 0
	currentIndex := 0

	for idx, test := range tests {
		testCloset.AddItem(test.inputName, test.inputColors, test.inputCategory, test.inputSubcategory)
		//first checks that item is added
		if testCloset.GetSize() <= currentSize {
			t.Errorf("\nTest case %d failed to add item", idx)
			continue
		}
		currentSize++
		//integrity check
		addedItem, err := testCloset.GetItem(currentIndex)
		if err != nil {
			t.Errorf("\nTest case %d failed to find item %d", idx, currentIndex)
		}
		if addedItem.GetName() == test.inputName &&
			reflect.DeepEqual(addedItem.GetColors(), test.inputColors) &&
			addedItem.GetCategory() == test.inputCategory &&
			addedItem.GetSubcategory() == test.inputSubcategory {
			t.Logf("\nTest case %d PASSED", idx)
		} else {
			t.Errorf("\nTest case %d FAILED: inaccurate item information:\n"+ //
				"Expected name: %s\tActual name %s\n"+ //
				"Expected colors: %v\tActual colors: %v"+ //
				"Expected category: %s\tActual category: %s\n"+ //
				"Expected subcategory: %d\tActual subcategory: %d\n",
				idx, test.inputName, addedItem.GetName(), cb.StringColors(test.inputColors), cb.StringColors(addedItem.GetColors()),
				test.inputCategory.String(), addedItem.GetCategory().String(), test.inputSubcategory, addedItem.GetSubcategory())
		}
		currentIndex++
		t.Logf("\nCurrent closet status:\n%s", testCloset.String())

	}

}
