package closetBuilder

import (
	h "OnlineCloset/src/helpers"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"time"
)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTS ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Constant error values for necessary info
const ERRNAME = "ERRORNAME"

var ERRCOLORS = []Color{COLORERROR}

const ERRID = -1

// Constant error values for extra info
var ERRDATE = time.Date(1969, time.April, 14, 12, 0, 0, 0, time.UTC)

const ERRPRICE = -1.0
const ERRWEARS = -1

// Constant empty values for extra info
var EMPTYDATE = time.Date(1968, time.August, 28, 12, 0, 0, 0, time.UTC)

const EMPTYPRICE = 0
const EMPTYWEARS = 0

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Item: an item of clothing
type Item struct {
	necessary     NecessaryInfo
	extra         ExtraInfo
	relationships ItemRelationships
}

// NecessaryInfo: All necessary information for each item from user
type NecessaryInfo struct {
	itemName        string
	itemColors      []Color
	itemCategory    Category
	itemSubcategory Subcategory
	itemID          int
}

// ExtraInfo: All extra information for each item
type ExtraInfo struct {
	itemDate  time.Time
	itemPrice float32
	itemWears int
	// TODO:
	// brand
	// weather
	// occasion
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTRUCTORS //////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Item constructor: takes in necessary data and creates new item
// if any necessary data isn't present, fails to create item
func CreateItem(name string, cs []Color, cat Category, subcat Subcategory, id int) *Item {
	n := CreateNecessaryInfo(name, cs, cat, subcat, id)
	if n == nil {
		return nil
	}

	return &Item{
		necessary:     *n,
		extra:         createEmptyExtra(),
		relationships: createItemRelationships(id),
	}
}

// NecessaryInfo constructor: takes in necessary data and creates new struct
func CreateNecessaryInfo(name string, cs []Color, cat Category, subcat Subcategory, id int) *NecessaryInfo {
	// checks name
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}
	// checks color
	if reflect.DeepEqual(cs, []Color{}) {
		return nil
	}
	cs = h.RemoveDuplicates(cs)
	// checks category
	if cat < TOP || cat > OTHER {
		return nil
	}
	possibleSubs := GetSubFromCat(cat)

	// checks subcategory: must align with category
	if subcat < TOPSTART || subcat > OTHERSTART || !slices.Contains(possibleSubs, subcat) {
		return nil
	}
	// checking id doesnt matter so proceeds to creation
	return &NecessaryInfo{
		itemName:        name,
		itemColors:      cs,
		itemCategory:    cat,
		itemSubcategory: subcat,
		itemID:          id,
	}
}

// ExtraInfo constructor: takes in extra data and creates new struct
func CreateExtraInfo(date time.Time, price float32, wears int) *ExtraInfo {
	// checks date: can't be in the future
	now := time.Now()
	if date.After(now) {
		return nil
	}
	// checks price: can't be negative
	if price < 0 {
		return nil
	}
	// checks wears: can't be negative
	if wears < 0 {
		return nil
	}
	return &ExtraInfo{
		itemDate:  date,
		itemPrice: price,
		itemWears: wears,
	}
}

//// EMPTY ITEM CONSTRUCTORS ///////////////////////////////////////////////////////////////////////////////
// these create "empty" or error structs to indicate failure or be used as placeholders

// Empty Item constructor: sets all item info to default values
func CreateEmptyItem() Item {
	return Item{
		necessary:     createEmptyNecessary(),
		extra:         createEmptyExtra(),
		relationships: createEmptyRelationships(),
	}
}

// Empty NecessaryInfo constructor: sets all necessary info to default values
func createEmptyNecessary() NecessaryInfo {
	return NecessaryInfo{
		itemName:        ERRNAME,
		itemColors:      ERRCOLORS,
		itemCategory:    CATEGORYERROR,
		itemSubcategory: SUBCATEGORYERROR,
		itemID:          ERRID,
	}
}

// Empty ExtraInfo constructor: sets all extra info to default values
func createEmptyExtra() ExtraInfo {
	return ExtraInfo{
		itemDate:  EMPTYDATE,
		itemPrice: EMPTYPRICE,
		itemWears: EMPTYWEARS,
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// // ITEM ACCESSORS ////////////////////////////////////////////////////////////////////////////////////////
func (o Item) GetName() string                        { return o.necessary.GetName() }
func (o Item) GetColors() []Color                     { return o.necessary.GetColors() }
func (o Item) GetCategory() Category                  { return o.necessary.GetCategory() }
func (o Item) GetSubcategory() Subcategory            { return o.necessary.GetSubcategory() }
func (o Item) GetID() int                             { return o.necessary.GetID() }
func (o Item) GetDate() time.Time                     { return o.extra.GetDate() }
func (o Item) GetPrice() float32                      { return o.extra.GetPrice() }
func (o Item) GetWears() int                          { return o.extra.GetWears() }
func (o Item) GetAllConnections() ConnectionsMap      { return o.relationships.GetAllConnections() }
func (o Item) GetAllOutfitsByItem() OutfitsByItemsMap { return o.relationships.GetAllOutfitsByItems() }
func (o Item) GetAllOutfits() AllOutfitsMap           { return o.relationships.GetAllOutfits() }

// TODO: add getters for specific connections and outfits

// // NECESSARYINFO ACCESSORS ///////////////////////////////////////////////////////////////////////////////
func (n NecessaryInfo) GetName() string             { return n.itemName }
func (n NecessaryInfo) GetColors() []Color          { return n.itemColors }
func (n NecessaryInfo) GetCategory() Category       { return n.itemCategory }
func (n NecessaryInfo) GetSubcategory() Subcategory { return n.itemSubcategory }
func (n NecessaryInfo) GetID() int                  { return n.itemID }

// // EXTRAINFO ACCESSORS ///////////////////////////////////////////////////////////////////////////////////
func (e ExtraInfo) GetDate() time.Time { return e.itemDate }
func (e ExtraInfo) GetPrice() float32  { return e.itemPrice }
func (e ExtraInfo) GetWears() int      { return e.itemWears }

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

//// NECESSARYINFO MUTATORS ////////////////////////////////////////////////////////////////////////////////

// SetName ensures new name isn't empty and removes leading/trailing whitespace
func (n *NecessaryInfo) SetName(newName string) {
	newName = strings.TrimSpace(newName)
	if newName == "" {
		return
	}
	n.itemName = newName
}

// SetColors ensures new colors isn't empty and doesn't contain duplicates
func (n *NecessaryInfo) SetColors(cs []Color) {
	cs = h.RemoveDuplicates(cs)
	for idx, c := range cs {
		if c < RED || c >= COLORERROR {
			cs = slices.Delete(cs, idx, idx+1)
			idx--
		}
	}
	if len(cs) == 0 {
		return
	}
	n.itemColors = cs
}

// category and subcategory must be set together to ensure same grouping
func (n *NecessaryInfo) SetCategories(c Category, s Subcategory) {
	if c < TOP || c > OTHER {
		return
	}
	possibleSubs := GetSubFromCat(c)
	if s < TOPSTART || s > OTHERSTART || !slices.Contains(possibleSubs, s) {
		return
	}

	n.itemCategory = c
	n.itemSubcategory = s
}

// subcategory can be edited independently if it is verified
func (n *NecessaryInfo) SetSubcategory(s Subcategory) {
	possibleSubs := GetSubFromCat(n.GetCategory())
	if s < TOPSTART || s > OTHERSTART || !slices.Contains(possibleSubs, s) {
		return
	}
	n.itemSubcategory = s
}

// SetID: sets ID and ensures it's nonnegative
func (n *NecessaryInfo) SetID(id int) {
	if id < 0 {
		return
	}
	n.itemID = id
}

//// EXTRAINFO MUTATORS ////////////////////////////////////////////////////////////////////////////////////

// SetDate takes in a concrete date and sets it if it isn't in the future
func (e *ExtraInfo) SetDate(newDate time.Time) {
	now := time.Now()
	if newDate.After(now) {
		return
	}
	e.itemDate = newDate
}

// SetPrice ensures price isn't negative
func (e *ExtraInfo) SetPrice(p float32) {
	if p < 0 {
		return
	}
	e.itemPrice = p
}

// SetWears ensures wears isn't negative
func (e *ExtraInfo) SetWears(w int) {
	if w < 0 || w > 10000 {
		return
	}
	e.itemWears = w
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// STRING ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (o Item) String() string {
	return o.necessary.String()
}

func (n NecessaryInfo) String() string {
	nString := "item ID:\t\t" + strconv.Itoa(n.itemID) + "\n" +
		"item name:\t\t" + n.itemName + "\n" +
		"item colors:\t\t" + strings.Join(StringColors(n.itemColors), ", ") + "\n" +
		"item category:\t\t" + n.itemCategory.String() + "\n" +
		"item subcategory:\t" + n.itemSubcategory.String() + "\n"
	return nString
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CUSTOMCOMPARABLE //////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
