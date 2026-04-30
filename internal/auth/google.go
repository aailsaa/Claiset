package auth

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
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

// cleanOAuthClientID trims spaces and accidental wrapping quotes from .env values.
func cleanOAuthClientID(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, `"`)
	s = strings.TrimSuffix(s, `"`)
	s = strings.TrimPrefix(s, `'`)
	s = strings.TrimSuffix(s, `'`)
	return strings.TrimSpace(s)
}

// googleClientAudiences returns OAuth client IDs to try when validating ID tokens.
// GOOGLE_CLIENT_ID may be a comma-separated list (e.g. Web + iOS) so the correct audience matches the JWT `aud`.
func googleClientAudiences() []string {
	raw := strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_ID"))
	if raw == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if s := cleanOAuthClientID(p); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// audFromJWTUnverified returns the JWT `aud` claim for error hints (not used for trust decisions).
func audFromJWTUnverified(token string) string {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return ""
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ""
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(payload, &m); err != nil {
		return ""
	}
	raw, ok := m["aud"]
	if !ok {
		return ""
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil && s != "" {
		return s
	}
	var arr []string
	if err := json.Unmarshal(raw, &arr); err == nil && len(arr) > 0 {
		return strings.Join(arr, ", ")
	}
	return ""
}

// BearerMiddleware validates Google ID tokens when GOOGLE_CLIENT_ID is set (supports comma-separated IDs).
// When unset, extracts "sub" from the JWT payload without verification (local dev only; do not use in production).
func BearerMiddleware(next http.Handler) http.Handler {
	audiences := googleClientAudiences()
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
		if len(audiences) > 0 {
			var payload *idtoken.Payload
			var lastErr error
			for _, aud := range audiences {
				payload, err = idtoken.Validate(r.Context(), token, aud)
				if err == nil {
					sub = payload.Subject
					break
				}
				lastErr = err
			}
			if sub == "" {
				hint := audFromJWTUnverified(token)
				msg := fmt.Sprintf("invalid token: %v", lastErr)
				if hint != "" {
					msg += fmt.Sprintf(" — JWT aud is %q; set GOOGLE_CLIENT_ID on each Go service to exactly match web/.env VITE_GOOGLE_CLIENT_ID (same OAuth Web client ID). Or unset GOOGLE_CLIENT_ID for local dev only.", hint)
				}
				http.Error(w, msg, http.StatusUnauthorized)
				return
			}
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
