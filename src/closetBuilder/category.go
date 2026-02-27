package closetBuilder

// Category represents possible types of artices of clothing
type Category int

// all category types as enum
const (
	TOP           Category = iota //0
	BOTTOMS                       //1
	OUTERWEAR                     //2
	ONEPIECE                      //3
	SHOES                         //4
	ACCESSORY                     //5
	JEWELRY                       //6
	BAG                           //7
	OTHER                         //8
	CATEGORYERROR                 //9
)

// map to convert enum back to string representation
var CategoryNames = map[Category]string{
	TOP:           "TOP",
	BOTTOMS:       "BOTTOMS",
	OUTERWEAR:     "OUTERWEAR",
	ONEPIECE:      "ONEPIECE",
	SHOES:         "SHOES",
	ACCESSORY:     "ACCESSORY",
	JEWELRY:       "JEWELRY",
	BAG:           "BAG",
	OTHER:         "OTHER",
	CATEGORYERROR: "CATEGORYERROR",
}

// string function for category
func (c Category) String() string {
	if c < TOP || c > OTHER {
		return ""
	}
	return CategoryNames[c]
}

// GetAllCategories returns a list of all categories, exluding the error value
func GetAllCategories() []Category {
	rval := []Category{}
	for i := TOP; i < CATEGORYERROR; i++ {
		rval = append(rval, i)
	}
	return rval
}

// GetAllCategoryStrings returns a list of all categories represented as strings
func GetAllCategoryStrings() []string {
	cats := GetAllCategories()
	rvals := []string{}
	for _, c := range cats {
		rvals = append(rvals, c.String())
	}
	return rvals
}

// IsValid: check if given category is valid
func (c Category) IsValid() bool {
	if c < TOP || c >= CATEGORYERROR {
		return false
	}
	return true
}
