package closet

import (
	"errors"
	"fmt"
	"strings"
)

/////TYPES//////////////////////////////////////////////////////////////////////////////////////////////////

// type LocalCloset holds all clothing items in a map, and counts the total number of items ever created
type LocalCloset struct {
	library    map[int]LocalItem
	totalItems int
	outfits    map[int]LocalOutfit
}

/////CONSTRUCTORS///////////////////////////////////////////////////////////////////////////////////////////

// CreateCloset creates an empty closet with a new library map
func CreateCloset() LocalCloset {
	return LocalCloset{
		library:    make(map[int]LocalItem),
		totalItems: 0,
		outfits:    make(map[int]LocalOutfit),
	}
}

// func BuildCloset(fileName string) LocalCloset {

// }

/////ACCESSORS//////////////////////////////////////////////////////////////////////////////////////////////

func (c LocalCloset) GetTotalItems() int { return c.totalItems }

func (c LocalCloset) GetSize() int { return len(c.library) }

func (c LocalCloset) GetItem(id int) (LocalItem, error) {
	i, exists := c.library[id]
	if !exists {
		return CreateEmptyItem(), errors.New("Error: item not found")
	}
	return i, nil
}

func (c LocalCloset) GetOutfit(id int) (LocalOutfit, error) {
	o, exists := c.outfits[id]
	if !exists {
		return CreateErrorOutfit(), errors.New("Error: outfit not found")
	}
	return o, nil
}

/////MUTATORS///////////////////////////////////////////////////////////////////////////////////////////////

func (c *LocalCloset) AddItem(name string, cs []Color, cat Category, subcat Subcategory) {
	newItem := CreateItem(name, cs, cat, subcat, c.totalItems)
	c.library[c.totalItems] = *newItem
	c.totalItems++
}

func (c *LocalCloset) RemoveItem(id int) (*LocalItem, error) {
	// checks if item exists
	val, exists := c.library[id]
	if !exists {
		return nil, errors.New("Error: item not found")
	}

	//goes through relationships and removes item from all other item's relationships
	connections := val.GetAllConnections()
	for otherID := range connections {
		otherItem, exists := c.GetItem(otherID)
		if exists != nil {
			continue
		}
		otherItem.relationships.RemoveConnection(val)
	}

	allOBI := val.GetAllOutfitsByItem()
	for otherID := range allOBI {
		otherItem, exists := c.GetItem(otherID)
		if exists != nil {
			continue
		}
		otherItem.relationships.RemoveItemOBI(val)
	}

	allOutfits := val.GetAllOutfits()
	for outfitID := range allOutfits {
		outfit, exists := c.GetOutfit(outfitID)
		if exists != nil {
			continue
		}
		outfit.RemoveItem(val)
	}

	// removes item from library
	delete(c.library, id)
	
	return &val, nil
}

/////STRING/////////////////////////////////////////////////////////////////////////////////////////////////

func (c LocalCloset) String() string {
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
