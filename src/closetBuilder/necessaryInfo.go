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

// error value for field name
const ERRNAME = "ERRORNAME"

// error value for field colors
var ERRCOLORS = []Color{COLORERROR}

// empty value for field colors
var EMPTYCOLORS = []Color{}

// error value for field itemID
const ERRID = -1

// custom error value for invalid struct
var ErrInvalidNecessaryInfo = errors.New("invalid necessary info")

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo: All necessary information for each item from user
type NecessaryInfo struct {
	name        string
	colors      []Color
	category    Category
	subcategory Subcategory
	itemID      int
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTRUCTORS //////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo constructor: take in necessary data and create new struct
func CreateNecessaryInfo(name string, cs []Color, cat Category, subcat Subcategory, id int) *NecessaryInfo {
	// check name
	name, err := IsValidName(name)
	if err != nil {
		return nil
	}
	// check color
	cs, err = IsValidColors(cs)
	if err != nil {
		return nil
	}

	// check category and subcategory
	cat, subcat, err = IsValidCategories(cat, subcat)
	if err != nil {
		return nil
	}

	// check id
	id, err = IsValidID(id)
	if err != nil {
		return nil
	}

	return &NecessaryInfo{
		name:        name,
		colors:      cs,
		category:    cat,
		subcategory: subcat,
		itemID:      id,
	}
}

// Empty NecessaryInfo constructor: set all necessary info to default values
func createEmptyNecessary() NecessaryInfo {
	return NecessaryInfo{
		name:        ERRNAME,
		colors:      ERRCOLORS,
		category:    CATEGORYERROR,
		subcategory: SUBCATEGORYERROR,
		itemID:      ERRID,
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (n NecessaryInfo) GetName() string             { return n.name }
func (n NecessaryInfo) GetColors() []Color          { return n.colors }
func (n NecessaryInfo) GetCategory() Category       { return n.category }
func (n NecessaryInfo) GetSubcategory() Subcategory { return n.subcategory }
func (n NecessaryInfo) GetID() int                  { return n.itemID }

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MUTATORS //////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// SetName: ensure new name isn't empty and remove leading/trailing whitespace
func (n *NecessaryInfo) SetName(newName string) {
	newName, err := IsValidName(newName)
	if err != nil {
		return
	}
	n.name = newName
}

// SetColors: ensure new colors list isn't empty and doesn't contain duplicates
func (n *NecessaryInfo) SetColors(cs []Color) {
	cs, err := IsValidColors(cs)
	if err != nil {
		return
	}
	n.colors = cs
}

// SetCategories: set category and subcategory toegether to ensure subcategory matches category
func (n *NecessaryInfo) SetCategories(c Category, s Subcategory) {
	c, s, err := IsValidCategories(c, s)
	if err != nil {
		return
	}
	n.category = c
	n.subcategory = s
}

// SetSubcategory: ensure new subcategory matches self category
func (n *NecessaryInfo) SetSubcategory(s Subcategory) {
	s, err := IsValidSubcategory(s)
	if err != nil {
		return
	}
	possibleSubs := GetSubFromCat(n.GetCategory())
	if s < TOPSTART || s > OTHERSTART || !slices.Contains(possibleSubs, s) {
		return
	}
	n.subcategory = s
}

// SetID: set ID and ensure it's nonnegative
func (n *NecessaryInfo) SetID(id int) {
	id, err := IsValidID(id)
	if err != nil {
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
		"item name:\t\t" + n.name + "\n" +
		"item colors:\t\t" + strings.Join(StringColors(n.colors), ", ") + "\n" +
		"item category:\t\t" + n.category.String() + "\n" +
		"item subcategory:\t" + n.subcategory.String() + "\n"
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// NECESSARYINFO VALIDATION //////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

// NecessaryInfo Equals: check if 2 NecessaryInfo structs are equal by going through each field
func (n NecessaryInfo) Equals(other NecessaryInfo) bool {
	return n.name == other.name &&
		reflect.DeepEqual(n.colors, other.colors) &&
		n.category == other.category &&
		n.subcategory == other.subcategory &&
		n.itemID == other.itemID
}

//// ISVALID ///////////////////////////////////////////////////////////////////////////////////////////////

// IsValid: check if NecessaryInfo is valid by going through all fields
// returns NecessaryInfo if validated or error if NecessaryInfo is invalid
func (n NecessaryInfo) IsValid() (*NecessaryInfo, error) {
	// if n is the generic empty/error necessaryInfo item, returns error flag
	if n.Equals(createEmptyNecessary()) {
		return nil, fmt.Errorf("necessary info is empty: %w", ErrInvalidNecessaryInfo)
	}

	// otherwise must go through all fields and check validity:
	// errs holds all possible errors from NecessaryInfo fields
	errs := []error{}

	// goes through all fields and checks validity, adding any errors to accumulator
	_, nErr := IsValidName(n.name)
	if nErr != nil {
		errs = append(errs, nErr)
	}

	_, cErr := IsValidColors(n.colors)
	if cErr != nil {
		errs = append(errs, cErr)
	}

	_, c2Err := IsValidCategory(n.category)
	if c2Err != nil {
		errs = append(errs, c2Err)
	}

	_, sErr := IsValidSubcategory(n.subcategory)
	if sErr != nil {
		errs = append(errs, sErr)
	}

	_, iErr := IsValidID(n.itemID)
	if iErr != nil {
		errs = append(errs, iErr)
	}

	// check if category and subcategory match
	if c2Err == nil && sErr == nil {
		if !slices.Contains(GetSubFromCat(n.category), n.subcategory) {
			errs = append(errs, fmt.Errorf("category and subcategory don't match: %w", ErrInvalidNecessaryInfo))
		}
	}

	if len(errs) == 0 {
		return &n, nil
	} else if len(errs) == 1 {
		return nil, errs[0]
	}
	return nil, errors.Join(errs...)
}

//// ISVALID: NECESSARYINFO FIELDS /////////////////////////////////////////////////////////////////////////

// IsValidName: check if given string is a valid name, and return validated name or error
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
	cs = util.RemoveDuplicates(cs)

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

// IsValidCategories: check if given category and subcategory match
func IsValidCategories(c Category, s Subcategory) (Category, Subcategory, error) {
	errs := []error{}

	c, err := IsValidCategory(c)
	if err != nil {
		errs = append(errs, err)
	}

	s, err = IsValidSubcategory(s)
	if err != nil {
		errs = append(errs, err)
	}

	allSubsFromCat := GetSubFromCat(c)
	if !slices.Contains(allSubsFromCat, s) {
		errs = append(errs, fmt.Errorf("category and subcategory don't match: %w", ErrInvalidNecessaryInfo))
	}

	if len(errs) == 0 {
		return c, s, nil
	} else {
		return CATEGORYERROR, SUBCATEGORYERROR, errors.Join(errs...)
	}
}

// IsValidID: check if given id is valid, and return validated id or error
func IsValidID(id int) (int, error) {
	if id >= 0 {
		return id, nil
	}
	return ERRID, fmt.Errorf("invalid id: %w", ErrInvalidExtraInfo)
}
