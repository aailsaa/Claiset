package closet

import (
	"errors"
	"reflect"
	"time"
)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTS ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Constant errors for invalid type
var ErrInvalidItem = errors.New("invalid item")

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// LocalItem: an item of clothing
// LocalItem implements the CustomComparable interface with functions GetID and Equals
type LocalItem struct {
	necessary     NecessaryInfo
	extra         ExtraInfo
	relationships LocalRelationships
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTRUCTORS //////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// CreateItem: take in necessary data and create new item
// if any necessary data isn't present, fail to create item
func CreateItem(name string, cs []Color, cat Category, subcat Subcategory, id int) *LocalItem {
	n := CreateNecessaryInfo(name, cs, cat, subcat, id)
	if n == nil {
		return nil
	}

	return &LocalItem{
		necessary:     *n,
		extra:         CreateEmptyExtra(),
		relationships: CreateRelationships(id),
	}
}

// CreateEmptyItem: set all item info to default values
func CreateEmptyItem() LocalItem {
	return LocalItem{
		necessary:     createEmptyNecessary(),
		extra:         CreateEmptyExtra(),
		relationships: createEmptyRelationships(),
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// // ITEM ACCESSORS ////////////////////////////////////////////////////////////////////////////////////////
// access necessary info through item
func (o LocalItem) GetName() string             { return o.necessary.GetName() }
func (o LocalItem) GetColors() []Color          { return o.necessary.GetColors() }
func (o LocalItem) GetCategory() Category       { return o.necessary.GetCategory() }
func (o LocalItem) GetSubcategory() Subcategory { return o.necessary.GetSubcategory() }
func (o LocalItem) GetID() int                  { return o.necessary.GetID() }

// access extra info through item
func (o LocalItem) GetDate() time.Time { return o.extra.GetDate() }
func (o LocalItem) GetPrice() float32  { return o.extra.GetPrice() }
func (o LocalItem) GetWears() int      { return o.extra.GetWears() }

// access relationship item:
// access whole relationship maps through item:
func (o LocalItem) GetAllConnections() ConnectionsMap      { return o.relationships.GetAllConnections() }
func (o LocalItem) GetAllOutfitsByItem() OutfitsByItemsMap { return o.relationships.GetAllOutfitsByItems() }
func (o LocalItem) GetAllOutfits() AllOutfitsMap           { return o.relationships.GetAllOutfits() }

// access specific getters:
func (o LocalItem) GetConnection(itemID int) float32 { return o.relationships.GetConnection(itemID) }
func (o LocalItem) GetOutfitsByItem(itemID int) map[int]*LocalOutfit {
	return o.relationships.GetOutfitsByItem(itemID)
}

// access checkers:
func (o LocalItem) HasConnection(itemID int) bool { return o.relationships.HasConnection(itemID) }
func (o LocalItem) HasItemInOBI(itemID int) bool  { return o.relationships.HasConnection(itemID) }
func (o LocalItem) HasOutfitInOBI(itemID int, outfit *LocalOutfit) bool {
	return o.relationships.HasOutfitInOBI(itemID, outfit)
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MUTATORS //////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// ITEM MUTATORS /////////////////////////////////////////////////////////////////////////////////////////

func (o *LocalItem) SetName(newName string)                  { o.necessary.SetName(newName) }
func (o *LocalItem) SetColors(cs []Color)                    { o.necessary.SetColors(cs) }
func (o *LocalItem) SetCategories(c Category, s Subcategory) { o.necessary.SetCategories(c, s) }
func (o *LocalItem) SetSubcategory(c Subcategory)            { o.necessary.SetSubcategory(c) }
func (o *LocalItem) SetID(id int)                            { o.necessary.SetID(id) }

func (o *LocalItem) SetDate(d time.Time) { o.extra.SetDate(d) }
func (o *LocalItem) SetPrice(p float32)  { o.extra.SetPrice(p) }
func (o *LocalItem) SetWears(w int)      { o.extra.SetWears(w) }

//TODO: add mutators for relationships

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// STRING ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// String: return all fields of item stringed together
func (o LocalItem) String() string {
	return o.necessary.String() + o.extra.String() + o.relationships.String()
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ITEM VALIDATION ///////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

// Equals: check if 2 LocalItem structs are equal
func (o LocalItem) Equals(other any) bool {
	otherItem, ok := other.(LocalItem)
	if !ok {
		return false
	}

	return o.GetID() == otherItem.GetID() &&
		o.GetName() == otherItem.GetName() &&
		reflect.DeepEqual(o.GetColors(), otherItem.GetColors()) &&
		o.GetCategory() == otherItem.GetCategory() &&
		o.GetSubcategory() == otherItem.GetSubcategory() &&
		o.GetDate().Equal(otherItem.GetDate()) &&
		o.GetPrice() == otherItem.GetPrice() &&
		o.GetWears() == otherItem.GetWears()
}

//// ISVALID ///////////////////////////////////////////////////////////////////////////////////////////////

// IsValid: check if item is valid by going through all fields of item
func (o LocalItem) IsValid() (*LocalItem, error) {
	errs := []error{}

	_, nErr := o.necessary.IsValid()
	if nErr != nil {
		errs = append(errs, nErr)
	}

	eErr := o.extra.IsValid()
	if eErr != nil {
		errs = append(errs, eErr)
	}

	rErr := o.relationships.IsValid()
	if rErr != nil {
		errs = append(errs, rErr)
	}

	if len(errs) == 0 {
		return &o, nil
	}

	return nil, errors.Join(errs...)

}
