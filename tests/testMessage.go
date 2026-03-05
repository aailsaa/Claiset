package tests

import (
	"strconv"
)

func TestMessage(idx int, passed bool) string {
	if passed {
		return "case " + strconv.Itoa(idx) + " PASSED"
	} else {
		return "case " + strconv.Itoa(idx) + " FAILED"
	}

}
