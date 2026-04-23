package closet

import (
	util "OnlineCloset/src/util"
	"errors"
	"fmt"
	"maps"
	"reflect"
)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTS ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

const EMPTYOUTFITID = -1
const ERROUTFITID = -2

// error value for invalid LocalOutfit
var ErrInvalidOutfit = errors.New("invalid outfit")

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

type LocalOutfit struct {
	name     string
	items    map[int]*LocalItem
	wears    int
	outfitID int

	// TODO: weather, occasion, tags?
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////CONSTRUCTORS///////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// CreateOutfit: create a new outfit given name, items and id
func CreateOutfit(name string, items []LocalItem, ID int) LocalOutfit {
	items = util.RemoveCustomDuplicates(items)
	itemMap := make(map[int]*LocalItem)
	for _, item := range items {
		_, iErr := item.IsValid()
		if iErr != nil {
			continue
		}
		itemMap[item.GetID()] = &item
	}

	return LocalOutfit{
		name:     name,
		items:    itemMap,
		wears:    0,
		outfitID: ID,
	}
}

// CreateEmptyOutfit: create a new outfit with empty values for all fields
func CreateEmptyOutfit() LocalOutfit {
	return LocalOutfit{
		name:     "new outfit",
		items:    make(map[int]*LocalItem),
		wears:    0,
		outfitID: EMPTYOUTFITID,
	}
}

// CreateErrorOutfit: create a new outfit with error values for all fields
func CreateErrorOutfit() LocalOutfit {
	return LocalOutfit{
		name:     ERRNAME,
		items:    nil,
		wears:    -1,
		outfitID: ERROUTFITID,
	}
}

// CreateCopyOutfit: create a new outfit with same items as given outfit
func CreateCopyOutfit(o LocalOutfit) LocalOutfit {
	newItems := maps.Clone(o.items)

	return LocalOutfit{
		items:    newItems,
		wears:    0,
		outfitID: EMPTYOUTFITID,
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////ACCESSORS//////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (o LocalOutfit) GetItems() map[int]*LocalItem { return o.items }

func (o LocalOutfit) GetItemsSlice() []*LocalItem {
	rval := []*LocalItem{}
	for _, v := range o.items {
		rval = append(rval, v)
	}
	return rval
}

func (o LocalOutfit) GetWears() int { return o.wears }

func (o LocalOutfit) GetID() int { return o.outfitID }

////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////MUTATORS///////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (o *LocalOutfit) SetItems(items []LocalItem) {
	items = util.RemoveCustomDuplicates(items)
	itemMap := make(map[int]*LocalItem)
	for _, item := range items {
		_, iErr := item.IsValid()
		if iErr != nil {
			continue
		}
		itemMap[item.GetID()] = &item
	}
	o.items = itemMap
}

func (o *LocalOutfit) SetWears(wears int) {
	if wears < 0 {
		return
	}
	o.wears = wears
}

func (o *LocalOutfit) AddWear() { o.wears++ }

func (o *LocalOutfit) SetOutfitID(outfitID int) { o.outfitID = outfitID }

func (o *LocalOutfit) RemoveItem(item LocalItem) {
	delete(o.items, item.GetID())
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// OUTFIT VALIDATION /////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

func (o LocalOutfit) Equals(other any) bool {
	otherO, ok := other.(LocalOutfit)
	if !ok {
		return false
	}

	return o.name == otherO.name &&
		reflect.DeepEqual(o.items, otherO.items) &&
		o.wears == otherO.wears &&
		o.outfitID == otherO.outfitID
}

//// ISVALID ///////////////////////////////////////////////////////////////////////////////////////////////

// IsValid: ensure outfit struct is valid
func (o LocalOutfit) IsValid() (*LocalOutfit, error) {
	// check if name is valid
	if o.name == ERRNAME {
		return nil, fmt.Errorf("error in name: %w", ErrInvalidOutfit)
	}

	// go through all items and check for error items
	for idx, item := range o.items {
		_, iErr := item.IsValid()
		if iErr != nil {
			return nil, fmt.Errorf("error in item %d: %w", idx, ErrInvalidOutfit)
		}
	}

	// check if wears is valid
	if o.wears < 0 {
		return nil, fmt.Errorf("invalid wears: %w", ErrInvalidOutfit)
	}

	// checks if id is valid
	if o.outfitID == ERROUTFITID {
		return nil, fmt.Errorf("error in ID: %w", ErrInvalidOutfit)
	}

	// otherwise returns item
	return &o, nil

}
