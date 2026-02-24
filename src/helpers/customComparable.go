package helpers

import "maps"

type CustomComparable interface {
	Equals(other any) bool
	GetID() int
}

func RemoveCustomDuplicates[T CustomComparable](input []T) []T {
	seen := make(map[int]T)
	for _, item := range input {
		id := item.GetID()
		_, exists := seen[id]
		if !exists {
			seen[id] = item
		}
	}

	rVal := []T{}
	for item := range maps.Values(seen) {
		rVal = append(rVal, item)
	}
	return rVal

}
