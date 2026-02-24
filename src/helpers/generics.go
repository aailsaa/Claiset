package helpers

// generics contains all generic helper functions used throughout the package

func RemoveDuplicates[T comparable](slice []T) []T {
	seen := make(map[T]struct{})
	rval := []T{}
	for _, t := range slice {
		_, exists := seen[t]
		if !exists {
			seen[t] = struct{}{}
			rval = append(rval, t)
		}
	}
	return rval
}
