package closetBuilder

import (
	"errors"
	"fmt"
	"strconv"
	"time"
)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// CONSTS ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Constant error values for extra info
var ERRDATE = time.Date(1969, time.April, 14, 12, 0, 0, 0, time.UTC)

const ERRPRICE = -1.0
const ERRWEARS = -1

// Constant empty values for extra info
var EMPTYDATE = time.Date(1968, time.August, 28, 12, 0, 0, 0, time.UTC)

const EMPTYPRICE = 0
const EMPTYWEARS = 0

// Constant error for invalid type
var ErrInvalidExtraInfo = errors.New("invalid extra info")

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TYPES /////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

// ExtraInfo constructor: take in extra data and create new struct
func CreateExtraInfo(date time.Time, price float32, wears int) *ExtraInfo {
	// check date:
	date, err := IsValidDate(date)
	if err != nil {
		return nil
	}

	// checks price: can't be negative
	price, err = IsValidPrice(price)
	if err != nil {
		return nil
	}

	// checks wears: can't be negative
	wears, err = IsValidWears(wears)
	if err != nil {
		return nil
	}

	return &ExtraInfo{
		itemDate:  date,
		itemPrice: price,
		itemWears: wears,
	}
}

// Empty ExtraInfo constructor: set all extra info to default values
func CreateEmptyExtra() ExtraInfo {
	return ExtraInfo{
		itemDate:  EMPTYDATE,
		itemPrice: EMPTYPRICE,
		itemWears: EMPTYWEARS,
	}
}

// Error ExtraInfo constructor: set all extra info to error values
func CreateErrorExtra() ExtraInfo {
	return ExtraInfo{
		itemDate:  ERRDATE,
		itemPrice: ERRPRICE,
		itemWears: ERRWEARS,
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ACCESSORS /////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

func (e ExtraInfo) GetDate() time.Time { return e.itemDate }
func (e ExtraInfo) GetPrice() float32  { return e.itemPrice }
func (e ExtraInfo) GetWears() int      { return e.itemWears }

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MUTATORS //////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// SetDate: ensure given date isn't in the future
func (e *ExtraInfo) SetDate(newDate time.Time) {
	newDate, err := IsValidDate(newDate)
	if err != nil {
		return
	}
	e.itemDate = newDate
}

// SetPrice: ensure price isn't negative
func (e *ExtraInfo) SetPrice(p float32) {
	p, err := IsValidPrice(p)
	if err != nil {
		return
	}
	e.itemPrice = p
}

// SetWears: ensure wears isn't negative
func (e *ExtraInfo) SetWears(w int) {
	w, err := IsValidWears(w)
	if err != nil {
		return
	}
	e.itemWears = w
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// STRING ////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ExtraInfo String: return formatted string of all fields in ExtraInfo
func (e ExtraInfo) String() string {
	eString := "item date:\t\t"
	if e.itemDate.Equal(EMPTYDATE) {
		eString += "NONE\n"
	} else {
		eString += e.itemDate.Format("01-02-2006") + "\n"
	}
	eString += "item price:\t\t$" + strconv.FormatFloat(float64(e.itemPrice), 'f', 2, 32) + "\n" +
		"item wears:\t\t" + strconv.Itoa(e.itemWears) + "\n"
	return eString
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// EXTRAINFO VALIDATION //////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

//// EQUALS ////////////////////////////////////////////////////////////////////////////////////////////////

func (e ExtraInfo) Equals(other ExtraInfo) bool {
	return e.itemDate.Equal(other.itemDate) &&
		e.itemPrice == other.itemPrice &&
		e.itemWears == other.itemWears
}

//// ISVALID ///////////////////////////////////////////////////////////////////////////////////////////////

// IsValid: check if given ExtraInfo struct is valid
func (e ExtraInfo) IsValid() error {
	if e.Equals(CreateErrorExtra()) {
		return fmt.Errorf("extra info is empty: %w", ErrInvalidExtraInfo)
	}

	errs := []error{}

	_, err := IsValidDate(e.itemDate)
	if err != nil {
		errs = append(errs, err)
	}

	_, err = IsValidPrice(e.itemPrice)
	if err != nil {
		errs = append(errs, err)
	}

	_, err = IsValidWears(e.itemWears)
	if err != nil {
		errs = append(errs, err)
	}

	if len(errs) == 0 {
		return nil
	}

	return errors.Join(errs...)
}

// IsValidDate: check if given date isn't in the future, and isn't too far in the past
func IsValidDate(d time.Time) (time.Time, error) {
	if d.Equal(ERRDATE) {
		return d, fmt.Errorf("error in date: %w", ErrInvalidExtraInfo)
	}

	rn := time.Now()
	if d.After(rn) {
		return ERRDATE, fmt.Errorf("invalid future date: %w", ErrInvalidExtraInfo)
	}

	if d.Before(rn.AddDate(-100, 0, 0)) {
		return ERRDATE, fmt.Errorf("invalid past date: %w", ErrInvalidExtraInfo)
	}

	return d, nil
}

// IsValidPrice: check if given price is positive
func IsValidPrice(p float32) (float32, error) {
	if p == ERRPRICE {
		return ERRPRICE, fmt.Errorf("error in price: %w", ErrInvalidExtraInfo)
	} else if p < 0 {
		return ERRPRICE, fmt.Errorf("invalid price: %w", ErrInvalidExtraInfo)
	}
	return p, nil
}

func IsValidWears(w int) (int, error) {
	if w == ERRWEARS {
		return ERRWEARS, fmt.Errorf("error in wears: %w", ErrInvalidExtraInfo)
	} else if w < 0 || w > 36525 {
		return ERRWEARS, fmt.Errorf("invalid wears: %w", ErrInvalidExtraInfo)
	}
	return w, nil
}
