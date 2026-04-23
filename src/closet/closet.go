package closet

type Closet interface {
	//accessors
	GetTotalItems() int 
	GetSize() int
	GetItem(id int) (Item, error)
	GetOutfit(id int) (Outfit, error)
	String() string
	//mutators
	AddItem(name string, cs []Color, cat Category, subcat Subcategory)
	RemoveItem(id int) (*Item, error)
}
