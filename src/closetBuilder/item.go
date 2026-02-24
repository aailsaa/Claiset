package closetBuilder

import (
	h "OnlineCloset/src/helpers"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"time"
)

/////CONSTS///////////////////////////////////////////////////////////////////////////////////////////////////

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

/////TYPES///////////////////////////////////////////////////////////////////////////////////////////////////

// type Item is an item of clothing
type Item struct {
	necessary NecessaryInfo
	extra     ExtraInfo
}

// All necessary information for each item
type NecessaryInfo struct {
	itemName        string
	itemColors      []Color
	itemCategory    Category
	itemSubcategory Subcategory
	itemID          int
}

// All extra information for each item
type ExtraInfo struct {
	itemDate  time.Time
	itemPrice float32
	itemWears int
	// TODO:
	// brand
	// weather
	// occasion
}

/////CONSTRUCTORS///////////////////////////////////////////////////////////////////////////////////////////

// default Item constructor: takes in necessary data and creates new item
// if any necessary data isn't present, fails to create item
func CreateItem(name string, cs []Color, cat Category, subcat Subcategory, id int) *Item {
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
	n := NecessaryInfo{
		itemName:        name,
		itemColors:      cs,
		itemCategory:    cat,
		itemSubcategory: subcat,
		itemID:          id,
	}
	return &Item{
		necessary: n,
		extra:     createEmptyExtra(), //sets empty upon creation
	}
}

// EMPTY ITEM CONSTRUCTORS:
// these create "empty" or error structs to indicate failure

// sets all extra info to default values
func createEmptyExtra() ExtraInfo {
	return ExtraInfo{
		itemDate:  EMPTYDATE,
		itemPrice: EMPTYPRICE,
		itemWears: EMPTYWEARS,
	}
}

// sets all necessary info to default values
func createEmptyNecessary() NecessaryInfo {
	return NecessaryInfo{
		itemName:        ERRNAME,
		itemColors:      ERRCOLORS,
		itemCategory:    CATEGORYERROR,
		itemSubcategory: SUBCATEGORYERROR,
		itemID:          ERRID,
	}
}

func CreateEmptyItem() Item {
	return Item{
		necessary: createEmptyNecessary(),
		extra:     createEmptyExtra(),
	}
}

/////ACCESSORS//////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo accessors
func (n NecessaryInfo) GetName() string             { return n.itemName }
func (n NecessaryInfo) GetColors() []Color          { return n.itemColors }
func (n NecessaryInfo) GetCategory() Category       { return n.itemCategory }
func (n NecessaryInfo) GetSubcategory() Subcategory { return n.itemSubcategory }
func (n NecessaryInfo) GetID() int                  { return n.itemID }

// ExtraInfo accessors
func (e ExtraInfo) GetDate() time.Time { return e.itemDate }
func (e ExtraInfo) GetPrice() float32  { return e.itemPrice }
func (e ExtraInfo) GetWears() int      { return e.itemWears }

// Item accessors
func (o Item) GetName() string             { return o.necessary.GetName() }
func (o Item) GetColors() []Color          { return o.necessary.GetColors() }
func (o Item) GetCategory() Category       { return o.necessary.GetCategory() }
func (o Item) GetSubcategory() Subcategory { return o.necessary.GetSubcategory() }
func (o Item) GetID() int                  { return o.necessary.GetID() }
func (o Item) GetDate() time.Time          { return o.extra.GetDate() }
func (o Item) GetPrice() float32           { return o.extra.GetPrice() }
func (o Item) GetWears() int               { return o.extra.GetWears() }

/////MUTATORS//////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo mutators

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
	if len(cs) == 0 {
		return
	}
	cs = h.RemoveDuplicates(cs)
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

// SetID requires no verification
func (n *NecessaryInfo) SetID(id int) {
	n.itemID = id
}

// ExtraInfo mutators

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
	if w < 0 {
		return
	}
	e.itemWears = w
}

// Item mutators
func (o Item) SetName(newName string)                  { o.necessary.SetName(newName) }
func (o Item) SetColors(cs []Color)                    { o.necessary.SetColors(cs) }
func (o Item) SetCategories(c Category, s Subcategory) { o.necessary.SetCategories(c, s) }
func (o Item) SetSubcategory(c Subcategory)            { o.necessary.SetSubcategory(c) }
func (o Item) SetID(id int)                            { o.necessary.SetID(id) }

func (o Item) SetDate(d time.Time) { o.extra.SetDate(d) }
func (o Item) SetPrice(p float32)  { o.extra.SetPrice(p) }
func (o Item) SetWears(w int)      { o.extra.SetWears(w) }

/////STRING/////////////////////////////////////////////////////////////////////////////////////////////////

func (n NecessaryInfo) String() string {
	nString := "item ID:\t\t" + strconv.Itoa(n.itemID) + "\n" +
		"item name:\t\t" + n.itemName + "\n" +
		"item colors:\t\t" + strings.Join(StringColors(n.itemColors), ", ") + "\n" +
		"item category:\t\t" + n.itemCategory.String() + "\n" +
		"item subcategory:\t" + n.itemSubcategory.String() + "\n"
	return nString
}

func (o Item) String() string {
	return o.necessary.String()
}
