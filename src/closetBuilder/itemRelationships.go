package closetBuilder

import (
	"strconv"
	"strings"
)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTS ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

const BADCONNECTION = float32(-10)
const NEUTRALCONNECTION = float32(0)
const PERFECTCONNECTION = float32(10)
const NOCONNECTION = float32(-11)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ItemRelationships: holds all connections to other items
type ItemRelationships struct {
	itemID         int               // the item these relationships are for
	connections    ConnectionsMap    // map of itemID to connection strength
	outfitsByItems OutfitsByItemsMap // map of other items to outfits with both items
	allOutfits     AllOutfitsMap     // map of all outfits the item is in
}

// ConnectionsMap: a map with itemID keys and connection strength values
type ConnectionsMap map[int]float32

// OutfitsByItemsMap: a map with other itemID keys and InnerOutfitMap values
type OutfitsByItemsMap map[int]InnerOutfitMap

// InnerOutfitMap: a map with outfitID keys and ptr outfit values, the inner map of outfitsByItems
type InnerOutfitMap map[int]*Outfit

// allOutfitsMap: a map of all outfits the current item is in, with outfitID keys and outfit values
type AllOutfitsMap map[int]*Outfit

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTRUCTORS //////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

/////// ITEM RELATIONSHIPS CONSTRUCTORS ////////////////////////////////////////////////////////////////////

// ItemRelationships constructor: creates empty connections and outfits maps for given itemID
func CreateItemRelationships(itemID int) ItemRelationships {
	return ItemRelationships{
		itemID:         itemID,
		connections:    make(ConnectionsMap),
		outfitsByItems: make(OutfitsByItemsMap),
		allOutfits:     make(AllOutfitsMap),
	}
}

// Empty ItemRelationships constructor: creates empty connections and outfits maps
func createEmptyRelationships() ItemRelationships {
	return ItemRelationships{
		itemID:         -1,
		connections:    make(ConnectionsMap),
		outfitsByItems: make(OutfitsByItemsMap),
		allOutfits:     make(AllOutfitsMap),
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// All getters: gets whole map ///////////////////////////////////////////////////////////////////////////

func (r ItemRelationships) GetItemID() int                          { return r.itemID }
func (r ItemRelationships) GetAllConnections() ConnectionsMap       { return r.connections }
func (r ItemRelationships) GetAllOutfitsByItems() OutfitsByItemsMap { return r.outfitsByItems }
func (r ItemRelationships) GetAllOutfits() AllOutfitsMap            { return r.allOutfits }

//// Specific getters: returns connection/outfit given an item /////////////////////////////////////////////

// GetConnection: returns connection strength for other item if it exists
func (r ItemRelationships) GetConnection(otherID int) float32 {
	strength, exists := r.connections[otherID]
	if !exists {
		return NOCONNECTION
	}
	return strength
}

// GetOutfitsByItem: returns map of outfits for other item if it exists
func (r ItemRelationships) GetOutfitsByItem(otherID int) map[int]*Outfit {
	outfits, exists := r.outfitsByItems[otherID]
	if !exists {
		return nil
	}
	return outfits
}

//// Relationship checkers: checks if there are any connections or outfits for the item ///////////////////

// HasConnection: checks for an item in the connections map
func (r ItemRelationships) HasConnection(otherID int) bool {
	_, exists := r.connections[otherID]
	return exists
}

// HasItemInOBI: checks for an item in the outfitByItem map
func (r ItemRelationships) HasItemInOBI(otherID int) bool {
	_, exists := r.outfitsByItems[otherID]
	return exists
}

// HasOutfitInOBI: checks for an outfit in the outfitByItem map for a given item
func (r ItemRelationships) HasOutfitInOBI(otherID int, outfit *Outfit) bool {
	_, exists := r.outfitsByItems[otherID]
	if !exists {
		return false
	}
	_, outfitExists := r.outfitsByItems[otherID][outfit.GetID()]
	return outfitExists
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MUTATORS //////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// CONNECTION MUTATORS ///////////////////////////////////////////////////////////////////////////////////

//// connection add ////////////////////////////////////////////////////////////////////////////////////////

// AddConnection: creates a new connection with other item and given strength
func (r *ItemRelationships) AddConnection(other Item, strength float32) {
	// if strength is invalid, returns without creating connection
	if strength < BADCONNECTION || strength > PERFECTCONNECTION {
		return
	}

	// if other item is the same as self, returns without creating connection
	otherID := other.GetID()
	if otherID == r.itemID {
		return
	}

	// if connection already exists, returns without creating connection
	_, exists := r.connections[otherID]
	if exists {
		return
	}

	// otherwise creates connection with user asserted strength
	r.connections[otherID] = strength
	// if other item doesn't have a relationship with current, creates connection for other item
	if other.relationships.HasConnection(r.itemID) {
		return
	}
	other.relationships.reciprocalAdd(r.itemID, strength)

}

// reciprocalAdd: adds a connection to the item relationships without checking for validity
// used for adding the other side of a connection in AddConnection
func (r *ItemRelationships) reciprocalAdd(otherID int, strength float32) {
	r.connections[otherID] = strength
}

//// connection set ////////////////////////////////////////////////////////////////////////////////////////

// SetConnection: updates connection strength for other item if connection exists
func (r *ItemRelationships) SetConnection(other Item, strength float32) {
	// if strength is invalid, returns without updating connection
	if strength < BADCONNECTION || strength > PERFECTCONNECTION {
		return
	}

	// if connection doesn't exist, returns without updating connection
	otherID := other.GetID()
	_, exists := r.connections[otherID]
	if !exists {
		return
	}

	// otherwise updates connection with given strength
	r.connections[otherID] = strength

	if other.relationships.GetConnection(r.itemID) == strength {
		return
	}
	// if other item doesn't have updated relationship with current, updates:
	if !other.relationships.HasConnection(r.itemID) {
		other.relationships.reciprocalAdd(r.itemID, strength)
	} else {
		other.relationships.reciprocalSet(r.itemID, strength)
	}
}

// reciprocalSet: sets a connection to the item relationships without checking for validity
// used for setting the other side of a connection in SetConnection
func (r *ItemRelationships) reciprocalSet(otherID int, strength float32) {
	r.connections[otherID] = strength
}

//// connection remove /////////////////////////////////////////////////////////////////////////////////////

// RemoveConnection: removes connection with other item if it exists
func (r *ItemRelationships) RemoveConnection(other Item) {
	// if connection doesn't exist, returns without removing connection
	otherID := other.GetID()
	_, exists := r.connections[otherID]
	if !exists {
		return
	}

	// otherwise removes connection
	delete(r.connections, otherID)
	if !other.relationships.HasConnection(r.itemID) {
		return
	}

	//if other item has relationship with current, removes it
	other.relationships.reciprocalRemove(r.itemID)

}

// reciprocalRemove: removes a connection to the item relationships without checking for validity
// used for removing the other side of a connection in RemoveConnection
func (r *ItemRelationships) reciprocalRemove(otherID int) {
	delete(r.connections, otherID)
}

//// OUTFITS BY ITEMS MUTATORS /////////////////////////////////////////////////////////////////////////////

// AddOutfitByItem: adds outfit to outfitByItem map for all items in the outfit
func (r *ItemRelationships) AddOutfitByItem(outfit *Outfit) {
	// first checks that self item is in outfit: if not, returns without adding outfit to map
	found := false
	outfitItems := outfit.GetItems()
	for _, item := range outfitItems {
		if item.GetID() == r.itemID {
			found = true
			break
		}
	}
	if !found {
		return
	}

	// goes though all items in outfit again and adds outfit to each item's InnerOutfitMap
	for _, item := range outfitItems {
		// skips self item
		if item.GetID() == r.itemID {
			continue
		}

		// updateID is the ID of the item whose InnerOutfitMap will be updated with the outfit
		updateID := item.GetID()

		// if item doesn't have an InnerOutfitMap in outfitsByItems, creates one and adds outfit
		innerMap, exists := r.outfitsByItems[updateID]
		if !exists {
			r.outfitsByItems[updateID] = make(InnerOutfitMap)
			innerMap = r.outfitsByItems[updateID]
			innerMap[outfit.GetID()] = outfit

			// if item already has an InnerOutfitMap, adds outfit to map if it isn't already there
		} else {
			_, outfitExists := innerMap[outfit.GetID()]
			if !outfitExists {
				innerMap[outfit.GetID()] = outfit
			}
		}
	}

}

// RemoveOutfitByItem: removes outfit from outfitByItem map for all items in the outfit
func (r *ItemRelationships) RemoveOutfitByItem(outfit *Outfit) {
	// first checks if self item is in outfit
	outfitItems := outfit.GetItems()
	found := false
	for _, item := range outfitItems {
		if item.GetID() == r.itemID {
			found = true
			break
		}
	}
	if !found {
		return
	}

	// then goes through all items in outfit again and removes outfit from each item's InnerOutfitMap
	for _, item := range outfitItems {
		// skips self item
		if item.GetID() == r.itemID {
			continue
		}

		// updateID is the ID of the item whose InnerOutfitMap will be updated by removing the outfit
		updateID := item.GetID()

		// if item doesn't have an InnerOutfitMap in outfitsByItems, continues to next item
		innerMap, exists := r.outfitsByItems[updateID]
		if !exists {
			continue
		}
		// if item has an InnerOutfitMap, removes outfit from map if it is there
		delete(innerMap, outfit.GetID())

		// if loop item's InnerOutfitMap is now empty, removes it from outfitsByItemsMap
		if len(innerMap) == 0 {
			delete(r.outfitsByItems, updateID)
		}
	}
}

// RemoveItemOBI: removes an item from outfitByItem map if it exists
func (r *ItemRelationships) RemoveItemOBI(other Item) {
	otherID := other.GetID()
	_, exists := r.outfitsByItems[otherID]
	if !exists {
		return
	}
	delete(r.outfitsByItems, otherID)
}

//// allOutfits mutators ///////////////////////////////////////////////////////////////////////////////////

// AddOutfit: adds outfit to allOutfits map
func (r *ItemRelationships) AddOutfit(outfit Outfit) {
	// if outfit is already in allOutfits, returns without adding
	_, exists := r.allOutfits[outfit.GetID()]
	if exists {
		return
	}
	// otherwise adds outfit to allOutfits map
	r.allOutfits[outfit.GetID()] = &outfit
}

// RemoveOutfit: removes outfit from allOutfits map if it exists
func (r *ItemRelationships) RemoveOutfit(outfit Outfit) {
	// if outfit isn't in allOutfits, returns without removing
	_, exists := r.allOutfits[outfit.GetID()]
	if !exists {
		return
	}
	// otherwise removes the outfit
	delete(r.allOutfits, outfit.GetID())
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// STRING ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (r ItemRelationships) String() string {
	if len(r.connections) == 0 && len(r.outfitsByItems) == 0 && len(r.allOutfits) == 0 {
		return "No relationships for item " + strconv.Itoa(r.itemID)
	}

	var sb strings.Builder
	sb.WriteString("Item relationships for item " + strconv.Itoa(r.itemID) + "\n")
	if len(r.connections) == 0 {
		sb.WriteString("No connections\n")
	} else {
		sb.WriteString(r.connections.String())
	}

	if len(r.outfitsByItems) == 0 {
		sb.WriteString("No outfits by item\n")
	} else {
		sb.WriteString(r.outfitsByItems.String())
	}

	if len(r.allOutfits) == 0 {
		sb.WriteString("No outfits with item " + strconv.Itoa(r.itemID) + "\n")
	} else {
		sb.WriteString(r.allOutfits.String())
	}

	return sb.String()
}

// ConnectionsMap String: returns string representation of connections map, unless map is empty
func (c ConnectionsMap) String() string {
	if len(c) == 0 {
		return ""
	}
	var sb strings.Builder
	sb.WriteString("Connections:\n")
	counter := 1
	for itemID, strength := range c {
		sb.WriteString("\t" + strconv.Itoa(counter) + ". Item " + strconv.Itoa(itemID) + ": " +
			strconv.FormatFloat(float64(strength), 'f', 2, 32) + "\n")
		counter++
	}
	return sb.String()
}

// OutfitsByItemsMap String: returns string representation of outfitsByItems map, unless map is empty
func (o OutfitsByItemsMap) String() string {
	if len(o) == 0 {
		return ""
	}
	var sb strings.Builder
	sb.WriteString("Outfits by item:\n")
	counter := 1
	for itemID, innerMap := range o {
		sb.WriteString(strconv.Itoa(counter) + ". Item " + strconv.Itoa(itemID) + ":\n")
		innerCounter := 1
		for outfitID := range innerMap {
			sb.WriteString("\t" + strconv.Itoa(innerCounter) + ". Outfit " + strconv.Itoa(outfitID) + "\n")
			innerCounter++
		}
		counter++
	}
	return sb.String()

}

// AllOutfitsMap String: returns string representation of allOutfits map, unless map is empty
func (a AllOutfitsMap) String() string {
	if len(a) == 0 {
		return ""
	}
	var sb strings.Builder
	sb.WriteString("All outfits:\n")
	counter := 1
	for outfitID := range a {
		sb.WriteString(strconv.Itoa(counter) + ". Outfit " + strconv.Itoa(outfitID) + "\n")
		counter++
	}
	return sb.String()
}
