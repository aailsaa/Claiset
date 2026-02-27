package closetBuilder

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

// Item: an item of clothing
// Item impelements the CustomComparable interface with functions GetID and Equals
type Item struct {
	necessary     NecessaryInfo
	extra         ExtraInfo
	relationships Relationships
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTRUCTORS //////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Item constructor: take in necessary data and create new item
// if any necessary data isn't present, fail to create item
func CreateItem(name string, cs []Color, cat Category, subcat Subcategory, id int) *Item {
	n := CreateNecessaryInfo(name, cs, cat, subcat, id)
	if n == nil {
		return nil
	}

	return &Item{
		necessary:     *n,
		extra:         createEmptyExtra(),
		relationships: CreateRelationships(id),
	}
}

// Empty Item constructor: set all item info to default values
func CreateEmptyItem() Item {
	return Item{
		necessary:     createEmptyNecessary(),
		extra:         createEmptyExtra(),
		relationships: createEmptyRelationships(),
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// // ITEM ACCESSORS ////////////////////////////////////////////////////////////////////////////////////////
// access necessary info through item
func (o Item) GetName() string             { return o.necessary.GetName() }
func (o Item) GetColors() []Color          { return o.necessary.GetColors() }
func (o Item) GetCategory() Category       { return o.necessary.GetCategory() }
func (o Item) GetSubcategory() Subcategory { return o.necessary.GetSubcategory() }
func (o Item) GetID() int                  { return o.necessary.GetID() }

// access extra info through item
func (o Item) GetDate() time.Time { return o.extra.GetDate() }
func (o Item) GetPrice() float32  { return o.extra.GetPrice() }
func (o Item) GetWears() int      { return o.extra.GetWears() }

// access relationship item:
// access whole relationship maps through item:
func (o Item) GetAllConnections() ConnectionsMap      { return o.relationships.GetAllConnections() }
func (o Item) GetAllOutfitsByItem() OutfitsByItemsMap { return o.relationships.GetAllOutfitsByItems() }
func (o Item) GetAllOutfits() AllOutfitsMap           { return o.relationships.GetAllOutfits() }

// access specific getters:
func (o Item) GetConnection(itemID int) float32 { return o.relationships.GetConnection(itemID) }
func (o Item) GetOutfitsByItem(itemID int) map[int]*Outfit {
	return o.relationships.GetOutfitsByItem(itemID)
}

// access checkers:
func (o Item) HasConnection(itemID int) bool { return o.relationships.HasConnection(itemID) }
func (o Item) HasItemInOBI(itemID int) bool  { return o.relationships.HasConnection(itemID) }
func (o Item) HasOutfitInOBI(itemID int, outfit *Outfit) bool {
	return o.relationships.HasOutfitInOBI(itemID, outfit)
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MUTATORS //////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// ITEM MUTATORS /////////////////////////////////////////////////////////////////////////////////////////

func (o *Item) SetName(newName string)                  { o.necessary.SetName(newName) }
func (o *Item) SetColors(cs []Color)                    { o.necessary.SetColors(cs) }
func (o *Item) SetCategories(c Category, s Subcategory) { o.necessary.SetCategories(c, s) }
func (o *Item) SetSubcategory(c Subcategory)            { o.necessary.SetSubcategory(c) }
func (o *Item) SetID(id int)                            { o.necessary.SetID(id) }

func (o *Item) SetDate(d time.Time) { o.extra.SetDate(d) }
func (o *Item) SetPrice(p float32)  { o.extra.SetPrice(p) }
func (o *Item) SetWears(w int)      { o.extra.SetWears(w) }

//TODO: add mutators for relationships

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// STRING ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Item String: return all fields of item stringed together
func (o Item) String() string {
	return o.necessary.String() + o.extra.String() + o.relationships.String()
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ITEM VALIDATION ///////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

// Equals: check if 2 Item structs are equal
func (o Item) Equals(other any) bool {
	otherItem, ok := other.(Item)
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

// IsValidItem: check if item is valid by going through all fields of item
// TODO
func IsValidItem(o Item) (bool, error) {
	return false, nil
}
