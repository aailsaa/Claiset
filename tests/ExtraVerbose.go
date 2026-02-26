package tests

import (
	"flag"
	"os"
	"testing"
)

var ExtraVerbose = flag.Bool("xv", false, "enable extra verbose output")

func TestMain(m *testing.M) {
	flag.Parse()
	os.Exit(m.Run())
}
