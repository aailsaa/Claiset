package closetBuilder

// Color represents possible color options for clothing to be tagged as.

type Color int

// all color options as enum
const (
	RED        Color = iota //0
	ORANGE                  //1
	YELLOW                  //2
	GREEN                   //3
	BLUE                    //4
	PURPLE                  //5
	PINK                    //6
	BROWN                   //7
	BLACK                   //8
	WHITE                   //9
	GREY                    //10
	SILVER                  //11
	GOLD                    //12
	MULTICOLOR              //13
	COLORERROR              //14
)

// map to convert the enum back to string value
var ColorNames = map[Color]string{
	RED:        "RED",
	ORANGE:     "ORANGE",
	YELLOW:     "YELLOW",
	GREEN:      "GREEN",
	BLUE:       "BLUE",
	PURPLE:     "PURPLE",
	PINK:       "PINK",
	BROWN:      "BROWN",
	BLACK:      "BLACK",
	WHITE:      "WHITE",
	GREY:       "GREY",
	SILVER:     "SILVER",
	GOLD:       "GOLD",
	MULTICOLOR: "MULTICOLOR",
	COLORERROR: "COLORERROR",
}

// STRING FUNCTIONS //

// converts single color to string representation
func (c Color) String() string {
	if c < RED || c > COLORERROR {
		return ""
	}
	return ColorNames[c]
}

// converts slice of colors to slice of strings (colors always stored in slice)
func StringColors(cs []Color) []string {
	rval := []string{}
	for _, c := range cs {
		rval = append(rval, c.String())
	}
	return rval
}

// GetAllColors returns a list of all colors
// not using map.values to retain order and omit default/error values
func GetAllColors() []string {
	rval := []string{}
	for i := RED; i < COLORERROR; i++ {
		rval = append(rval, ColorNames[i])
	}
	return rval
}
