package closetBuilder

import (
	"errors"
	"fmt"
	"strings"
)

/////TYPES//////////////////////////////////////////////////////////////////////////////////////////////////

// type Closet holds all clothing items in a map, and counts the total number of items ever created
type Closet struct {
	library    map[int]Item
	totalItems int
	outfits    map[int]Outfit
}

/////CONSTRUCTORS///////////////////////////////////////////////////////////////////////////////////////////

// CreateCloset creates an empty closet with a new library map
func CreateCloset() Closet {
	return Closet{
		library:    make(map[int]Item),
		totalItems: 0,
		outfits:    make(map[int]Outfit),
	}
}

// func BuildCloset(fileName string) Closet {

// }

/////ACCESSORS//////////////////////////////////////////////////////////////////////////////////////////////

func (c Closet) GetTotalItems() int { return c.totalItems }

func (c Closet) GetSize() int { return len(c.library) }

func (c Closet) GetItem(id int) (Item, error) {
	i, exists := c.library[id]
	if !exists {
		return CreateEmptyItem(), errors.New("Error: item not found")
	}
	return i, nil
}

/////MUTATORS///////////////////////////////////////////////////////////////////////////////////////////////

func (c *Closet) AddItem(name string, cs []Color, cat Category, subcat Subcategory) {
	newItem := CreateItem(name, cs, cat, subcat, c.totalItems)
	c.library[c.totalItems] = *newItem
	c.totalItems++
}

/////STRING/////////////////////////////////////////////////////////////////////////////////////////////////

func (c Closet) String() string {
	if c.GetSize() == 0 {
		return "closet is empty"
	}

	var sb strings.Builder
	sb.WriteString("ALL ITEMS:\n")
	counter := 1
	for _, item := range c.library {
		fmt.Fprintf(&sb, "ITEM %d\n", counter)
		counter++
		fmt.Fprintf(&sb, "%s\n", item.String())
	}
	fmt.Fprintf(&sb, "TOTAL CURRENT ITEMS: %d\nTOTAL EVER ITEMS: %d\n", c.GetSize(), c.GetTotalItems())
	return sb.String()
}
