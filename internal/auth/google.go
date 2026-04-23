package auth

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"

	"google.golang.org/api/idtoken"
)

type ctxKey int

const userSubKey ctxKey = 1

// UserSub returns the authenticated Google subject from the request context.
func UserSub(ctx context.Context) (string, bool) {
	v, ok := ctx.Value(userSubKey).(string)
	return v, ok && v != ""
}

// BearerMiddleware validates Google ID tokens when GOOGLE_CLIENT_ID is set.
// When unset, extracts "sub" from the JWT payload without verification (local dev only; do not use in production).
func BearerMiddleware(next http.Handler) http.Handler {
	clientID := strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_ID"))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw := strings.TrimSpace(r.Header.Get("Authorization"))
		if !strings.HasPrefix(strings.ToLower(raw), "bearer ") {
			http.Error(w, "missing Authorization: Bearer", http.StatusUnauthorized)
			return
		}
		token := strings.TrimSpace(raw[7:])
		if token == "" {
			http.Error(w, "empty bearer token", http.StatusUnauthorized)
			return
		}

		var sub string
		var err error
		if clientID != "" {
			var payload *idtoken.Payload
			payload, err = idtoken.Validate(r.Context(), token, clientID)
			if err != nil {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}
			sub = payload.Subject
		} else {
			sub, err = subFromJWTUnverified(token)
			if err != nil || sub == "" {
				http.Error(w, "invalid token (set GOOGLE_CLIENT_ID for full verification)", http.StatusUnauthorized)
				return
			}
		}

		ctx := context.WithValue(r.Context(), userSubKey, sub)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func subFromJWTUnverified(token string) (string, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", errors.New("not a jwt")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", err
	}
	var claims struct {
		Sub string `json:"sub"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return "", err
	}
	return claims.Sub, nil
}
