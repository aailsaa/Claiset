package closetBuilder

import (
	util "OnlineCloset/src/util"
	"errors"
	"fmt"
	"reflect"
	"slices"
	"strconv"
	"strings"
)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTS ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Constant error values for necessary info
const ERRNAME = "ERRORNAME"

var ERRCOLORS = []Color{COLORERROR}
var EMPTYCOLORS = []Color{}

const ERRID = -1

var ErrInvalidNecessaryInfo = errors.New("invalid necessary info")

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo: All necessary information for each item from user
type NecessaryInfo struct {
	itemName        string
	itemColors      []Color
	itemCategory    Category
	itemSubcategory Subcategory
	itemID          int
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTRUCTORS //////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo constructor: take in necessary data and create new struct
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
	cs = util.RemoveDuplicates(cs)
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

// Empty NecessaryInfo constructor: set all necessary info to default values
func createEmptyNecessary() NecessaryInfo {
	return NecessaryInfo{
		itemName:        ERRNAME,
		itemColors:      ERRCOLORS,
		itemCategory:    CATEGORYERROR,
		itemSubcategory: SUBCATEGORYERROR,
		itemID:          ERRID,
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (n NecessaryInfo) GetName() string             { return n.itemName }
func (n NecessaryInfo) GetColors() []Color          { return n.itemColors }
func (n NecessaryInfo) GetCategory() Category       { return n.itemCategory }
func (n NecessaryInfo) GetSubcategory() Subcategory { return n.itemSubcategory }
func (n NecessaryInfo) GetID() int                  { return n.itemID }

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MUTATORS //////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// SetName: ensure new name isn't empty and remove leading/trailing whitespace
func (n *NecessaryInfo) SetName(newName string) {
	newName = strings.TrimSpace(newName)
	if newName == "" {
		return
	}
	n.itemName = newName
}

// SetColors: ensure new colors list isn't empty and doesn't contain duplicates
func (n *NecessaryInfo) SetColors(cs []Color) {
	cs = util.RemoveDuplicates(cs)
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

// SetCategories: set category and subcategory toegether to ensure subcategory matches category
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

// SetSubcategory: ensure new subcategory matches self category
func (n *NecessaryInfo) SetSubcategory(s Subcategory) {
	possibleSubs := GetSubFromCat(n.GetCategory())
	if s < TOPSTART || s > OTHERSTART || !slices.Contains(possibleSubs, s) {
		return
	}
	n.itemSubcategory = s
}

// SetID: set ID and ensure it's nonnegative
func (n *NecessaryInfo) SetID(id int) {
	if id < 0 {
		return
	}
	n.itemID = id
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// STRING ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo String: return formatted string of all fields in NecessaryInfo
func (n NecessaryInfo) String() string {
	return "item ID:\t\t" + strconv.Itoa(n.itemID) + "\n" +
		"item name:\t\t" + n.itemName + "\n" +
		"item colors:\t\t" + strings.Join(StringColors(n.itemColors), ", ") + "\n" +
		"item category:\t\t" + n.itemCategory.String() + "\n" +
		"item subcategory:\t" + n.itemSubcategory.String() + "\n"
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ITEM VALIDATION ///////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo Equals: check if 2 NecessaryInfo structs are equal by going through each field
func (n NecessaryInfo) Equals(other NecessaryInfo) bool {
	return n.itemName == other.itemName &&
		reflect.DeepEqual(n.itemColors, other.itemColors) &&
		n.itemCategory == other.itemCategory &&
		n.itemSubcategory == other.itemSubcategory &&
		n.itemID == other.itemID
}

//// ISVALID ///////////////////////////////////////////////////////////////////////////////////////////////

// IsValidNecessaryInfo: check if NecessaryInfo is valid by going through all fields
// returns error if NecessaryInfo is invalid
func IsValidNecessaryInfo(n NecessaryInfo) error {
	// if n is the generic empty/error necessaryInfo item, returns error flag
	if n.Equals(createEmptyNecessary()) {
		return fmt.Errorf("necessary info is empty: %w", ErrInvalidNecessaryInfo)
	}

	// otherwise must go through all fields and check validity:
	// errs holds all possible errors from NecessaryInfo fields
	errs := []error{}

	// goes through all fields and checks validity, adding any errors to accumulator
	_, nErr := IsValidName(n.itemName)
	if nErr != nil {
		errs = append(errs, nErr)
	}

	_, cErr := IsValidColors(n.itemColors)
	if cErr != nil {
		errs = append(errs, cErr)
	}

	_, c2Err := IsValidCategory(n.itemCategory)
	if c2Err != nil {
		errs = append(errs, c2Err)
	}

	_, sErr := IsValidSubcategory(n.itemSubcategory)
	if sErr != nil {
		errs = append(errs, sErr)
	}

	_, iErr := IsValidID(n.itemID)
	if iErr != nil {
		errs = append(errs, iErr)
	}

	// check if category and subcategory match
	if c2Err == nil && sErr == nil {
		if !slices.Contains(GetSubFromCat(n.itemCategory), n.itemSubcategory) {
			errs = append(errs, fmt.Errorf("category and subcategory don't match: %w", ErrInvalidNecessaryInfo))
		}
	}

	if len(errs) == 0 {
		return nil
	} else if len(errs) == 1 {
		return errs[0]
	}
	return errors.Join(errs...)
}

//// ISVALID: NECESSARYINFO FIELDS /////////////////////////////////////////////////////////////////////////

// IsValidName: check if given string is a valid name,  and return validated name or error
func IsValidName(n string) (string, error) {
	n = strings.TrimSpace(n)
	switch n {
	case ERRNAME:
		return "", fmt.Errorf("error in name: %w", ErrInvalidNecessaryInfo)
	case "":
		return "", fmt.Errorf("name is empty: %w", ErrInvalidNecessaryInfo)
	}
	return n, nil
}

// IsValidColors: check if given colors are valid, and return validated & sorted colors or error
func IsValidColors(cs []Color) ([]Color, error) {
	slices.Sort(cs)

	if reflect.DeepEqual(cs, ERRCOLORS) || slices.Contains(cs, COLORERROR) {
		return EMPTYCOLORS, fmt.Errorf("error in colors: %w", ErrInvalidNecessaryInfo)

	} else if reflect.DeepEqual(cs, EMPTYCOLORS) {
		return EMPTYCOLORS, fmt.Errorf("colors is empty: %w", ErrInvalidNecessaryInfo)
	}
	return cs, nil
}

// IsValidCategory: check if given category is valid, and return validated category or error
func IsValidCategory(c Category) (Category, error) {
	if !c.IsValid() {
		return CATEGORYERROR, fmt.Errorf("error in category: %w", ErrInvalidNecessaryInfo)
	}
	return c, nil
}

// IsValidSubcategory: check if given subcategory is valid, and return validated subcategory or error
func IsValidSubcategory(s Subcategory) (Subcategory, error) {
	if s.IsValid() {
		return s, nil
	}
	return SUBCATEGORYERROR, fmt.Errorf("error in subcategory: %w", ErrInvalidNecessaryInfo)
}

// IsValidID: check if given id is valid, and return validated id or error
func IsValidID(id int) (int, error) {
	if id >= 0 {
		return id, nil
	}
	return ERRID, fmt.Errorf("invalid id: %w", ErrInvalidExtraInfo)
}
