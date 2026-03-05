package closetBuilder

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

// error value for invalid Outfit
var ErrInvalidOutfit = errors.New("invalid outfit")

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

type Outfit struct {
	name     string
	items    map[int]*Item
	wears    int
	outfitID int

	// TODO: weather, occasion, tags?
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////CONSTRUCTORS///////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// CreateOutfit: create a new outfit given name, items and id
func CreateOutfit(name string, items []Item, ID int) Outfit {
	items = util.RemoveCustomDuplicates(items)
	itemMap := make(map[int]*Item)
	for _, item := range items {
		_, iErr := IsValidItem(item)
		if iErr != nil {
			continue
		}
		itemMap[item.GetID()] = &item
	}

	return Outfit{
		name:     name,
		items:    itemMap,
		wears:    0,
		outfitID: ID,
	}
}

// CreateEmptyOutfit: create a new outfit with empty values for all fields
func CreateEmptyOutfit() Outfit {
	return Outfit{
		name:     "new outfit",
		items:    make(map[int]*Item),
		wears:    0,
		outfitID: EMPTYOUTFITID,
	}
}

// CreateErrorOutfit: create a new outfit with error values for all fields
func CreateErrorOutfit() Outfit {
	return Outfit{
		name:     ERRNAME,
		items:    nil,
		wears:    -1,
		outfitID: ERROUTFITID,
	}
}

// CreateCopyOutfit: create a new outfit with same items as given outfit
func CreateCopyOutfit(o Outfit) Outfit {
	newItems := maps.Clone(o.items)

	return Outfit{
		items:    newItems,
		wears:    0,
		outfitID: EMPTYOUTFITID,
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////ACCESSORS//////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (o Outfit) GetItems() map[int]*Item { return o.items }

func (o Outfit) GetItemsSlice() []*Item {
	rval := []*Item{}
	for _, v := range o.items {
		rval = append(rval, v)
	}
	return rval
}

func (o Outfit) GetWears() int { return o.wears }

func (o Outfit) GetID() int { return o.outfitID }

////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////MUTATORS///////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (o *Outfit) SetItems(items []Item) {
	items = util.RemoveCustomDuplicates(items)
	itemMap := make(map[int]*Item)
	for _, item := range items {
		_, iErr := IsValidItem(item)
		if iErr != nil {
			continue
		}
		itemMap[item.GetID()] = &item
	}
	o.items = itemMap
}

func (o *Outfit) SetWears(wears int) {
	if wears < 0 {
		return
	}
	o.wears = wears
}

func (o *Outfit) AddWear() { o.wears++ }

func (o *Outfit) SetOutfitID(outfitID int) { o.outfitID = outfitID }

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// OUTFIT VALIDATION /////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

func (o Outfit) Equals(other any) bool {
	otherO, ok := other.(Outfit)
	if !ok {
		return false
	}

	return o.name == otherO.name &&
		reflect.DeepEqual(o.items, otherO.items) &&
		o.wears == otherO.wears &&
		o.outfitID == otherO.outfitID
}

//// ISVALID ///////////////////////////////////////////////////////////////////////////////////////////////

// IsValidOutfit: ensure outfit struct is valid
func IsValidOutfit(o Outfit) (*Outfit, error) {
	// check if name is valid
	if o.name == ERRNAME {
		return nil, fmt.Errorf("error in name: %w", ErrInvalidOutfit)
	}

	// go through all items and check for error items
	for idx, item := range o.items {
		_, iErr := IsValidItem(*item)
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
