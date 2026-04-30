package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"

	"OnlineCloset/internal/auth"
	"OnlineCloset/internal/httpserver"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Outfit struct {
	ID           int             `json:"id"`
	Name         string          `json:"name"`
	Wears        int             `json:"wears"`
	ItemIDs      []int           `json:"itemIds"`
	CoverDataURL *string         `json:"coverDataUrl,omitempty"`
	Extra        json.RawMessage `json:"extra"`
	Layout       json.RawMessage `json:"layout"`
	Pictures     json.RawMessage `json:"pictures"`
}

type createOutfitBody struct {
	Name         string          `json:"name"`
	Wears        *int            `json:"wears,omitempty"`
	ItemIDs      []int           `json:"itemIds"`
	CoverDataURL *string         `json:"coverDataUrl,omitempty"`
	Extra        json.RawMessage `json:"extra,omitempty"`
	Layout       json.RawMessage `json:"layout,omitempty"`
	Pictures     json.RawMessage `json:"pictures,omitempty"`
}

type memRow struct {
	Outfit
	UserSub string
}

type memOutfitStore struct {
	mu   sync.Mutex
	next int
	rows []memRow
}

func (m *memOutfitStore) list(user string) []Outfit {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Outfit
	for _, r := range m.rows {
		if r.UserSub == user {
			out = append(out, r.Outfit)
		}
	}
	return out
}

func (m *memOutfitStore) add(user string, o Outfit) Outfit {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.next++
	o.ID = m.next
	if o.ItemIDs == nil {
		o.ItemIDs = []int{}
	}
	if len(o.Extra) == 0 {
		o.Extra = json.RawMessage(`{}`)
	}
	if len(o.Layout) == 0 {
		o.Layout = json.RawMessage(`[]`)
	}
	if len(o.Pictures) == 0 {
		o.Pictures = json.RawMessage(`[]`)
	}
	m.rows = append(m.rows, memRow{Outfit: o, UserSub: user})
	return o
}

func (m *memOutfitStore) get(user string, id int) (Outfit, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.rows {
		if r.UserSub == user && r.Outfit.ID == id {
			return r.Outfit, true
		}
	}
	return Outfit{}, false
}

func (m *memOutfitStore) update(user string, id int, next Outfit) (Outfit, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, r := range m.rows {
		if r.UserSub == user && r.Outfit.ID == id {
			next.ID = id
			if next.ItemIDs == nil {
				next.ItemIDs = []int{}
			}
			if len(next.Extra) == 0 {
				next.Extra = json.RawMessage(`{}`)
			}
			if len(next.Layout) == 0 {
				next.Layout = json.RawMessage(`[]`)
			}
			if len(next.Pictures) == 0 {
				next.Pictures = json.RawMessage(`[]`)
			}
			m.rows[i].Outfit = next
			return next, true
		}
	}
	return Outfit{}, false
}

func (m *memOutfitStore) delete(user string, id int) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, r := range m.rows {
		if r.UserSub == user && r.Outfit.ID == id {
			m.rows = append(m.rows[:i], m.rows[i+1:]...)
			return true
		}
	}
	return false
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	var pool *pgxpool.Pool
	if dsn != "" {
		ctx := context.Background()
		p, err := pgxpool.New(ctx, dsn)
		if err != nil {
			log.Fatalf("outfits-service: database: %v", err)
		}
		pool = p
		defer pool.Close()
		log.Println("outfits-service: using PostgreSQL (RDS / compose)")
	} else {
		log.Println("outfits-service: DATABASE_URL unset — using in-memory store (dev only)")
	}
	if os.Getenv("GOOGLE_CLIENT_ID") == "" {
		log.Println("outfits-service: GOOGLE_CLIENT_ID unset — Bearer token used as raw user id (dev only)")
	}

	mem := &memOutfitStore{}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(func(next http.Handler) http.Handler { return httpserver.DevCORS(next) })

	r.Get("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"service": "outfits", "status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Use(auth.BearerMiddleware)

		r.Get("/outfits", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			if pool == nil {
				_ = json.NewEncoder(w).Encode(mem.list(user))
				return
			}
			ctx := req.Context()
			rows, err := pool.Query(ctx, `
				SELECT o.id, o.name, o.wears, o.cover_data_url, o.extra, o.layout, o.pictures,
					COALESCE(
						(SELECT json_agg(oi.item_id ORDER BY oi.item_id)
						 FROM outfit_items oi WHERE oi.outfit_id = o.id),
						'[]'::json
					) AS item_ids
				FROM outfits o WHERE o.user_sub = $1 ORDER BY o.id`, user)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer rows.Close()
			var list []Outfit
			for rows.Next() {
				var o Outfit
				var raw []byte
				if err := rows.Scan(&o.ID, &o.Name, &o.Wears, &o.CoverDataURL, &o.Extra, &o.Layout, &o.Pictures, &raw); err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				if len(raw) > 0 {
					_ = json.Unmarshal(raw, &o.ItemIDs)
				}
				if o.ItemIDs == nil {
					o.ItemIDs = []int{}
				}
				if len(o.Extra) == 0 {
					o.Extra = json.RawMessage(`{}`)
				}
				if len(o.Layout) == 0 {
					o.Layout = json.RawMessage(`[]`)
				}
				if len(o.Pictures) == 0 {
					o.Pictures = json.RawMessage(`[]`)
				}
				list = append(list, o)
			}
			_ = json.NewEncoder(w).Encode(list)
		})

		r.Post("/outfits", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			var body createOutfitBody
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if body.Name == "" {
				http.Error(w, "name required", http.StatusBadRequest)
				return
			}
			if body.ItemIDs == nil {
				body.ItemIDs = []int{}
			}
			if len(body.Extra) == 0 {
				body.Extra = json.RawMessage(`{}`)
			}
			if len(body.Layout) == 0 {
				body.Layout = json.RawMessage(`[]`)
			}
			if len(body.Pictures) == 0 {
				body.Pictures = json.RawMessage(`[]`)
			}
			w.Header().Set("Content-Type", "application/json")

			if pool == nil {
				wears := 0
				if body.Wears != nil {
					wears = *body.Wears
				}
				o := mem.add(user, Outfit{Name: body.Name, Wears: wears, ItemIDs: body.ItemIDs, CoverDataURL: body.CoverDataURL, Extra: body.Extra, Layout: body.Layout, Pictures: body.Pictures})
				w.WriteHeader(http.StatusCreated)
				_ = json.NewEncoder(w).Encode(o)
				return
			}

			ctx := req.Context()
			if len(body.ItemIDs) > 0 {
				var n int
				err := pool.QueryRow(ctx, `
					SELECT COUNT(*) FROM items WHERE user_sub = $1 AND id = ANY($2::int[])`,
					user, body.ItemIDs).Scan(&n)
				if err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				if n != len(body.ItemIDs) {
					http.Error(w, "one or more item ids are invalid or belong to another user", http.StatusBadRequest)
					return
				}
			}

			tx, err := pool.Begin(ctx)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer tx.Rollback(ctx)

			var id int
			wears := 0
			if body.Wears != nil {
				wears = *body.Wears
			}
			if err := tx.QueryRow(ctx, `INSERT INTO outfits (user_sub, name, wears, cover_data_url, extra, layout, pictures) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`, user, body.Name, wears, body.CoverDataURL, body.Extra, body.Layout, body.Pictures).Scan(&id); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			for _, itemID := range body.ItemIDs {
				if _, err := tx.Exec(ctx, `INSERT INTO outfit_items (outfit_id, item_id) VALUES ($1, $2)`, id, itemID); err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
			}
			if err := tx.Commit(ctx); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			o := Outfit{ID: id, Name: body.Name, Wears: wears, ItemIDs: body.ItemIDs, CoverDataURL: body.CoverDataURL, Extra: body.Extra, Layout: body.Layout, Pictures: body.Pictures}
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(o)
		})

		r.Get("/outfits/{id}", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			idStr := chi.URLParam(req, "id")
			id, err := strconv.Atoi(idStr)
			if err != nil {
				http.Error(w, "bad id", http.StatusBadRequest)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			if pool == nil {
				if o, ok := mem.get(user, id); ok {
					_ = json.NewEncoder(w).Encode(o)
					return
				}
				http.NotFound(w, req)
				return
			}
			ctx := req.Context()
			var o Outfit
			var raw []byte
			err = pool.QueryRow(ctx, `
				SELECT o.id, o.name, o.wears, o.cover_data_url, o.extra, o.layout, o.pictures,
					COALESCE(
						(SELECT json_agg(oi.item_id ORDER BY oi.item_id)
						 FROM outfit_items oi WHERE oi.outfit_id = o.id),
						'[]'::json
					) AS item_ids
				FROM outfits o WHERE o.id = $1 AND o.user_sub = $2`, id, user,
			).Scan(&o.ID, &o.Name, &o.Wears, &o.CoverDataURL, &o.Extra, &o.Layout, &o.Pictures, &raw)
			if err != nil {
				http.NotFound(w, req)
				return
			}
			if len(raw) > 0 {
				_ = json.Unmarshal(raw, &o.ItemIDs)
			}
			if o.ItemIDs == nil {
				o.ItemIDs = []int{}
			}
			if len(o.Extra) == 0 {
				o.Extra = json.RawMessage(`{}`)
			}
			if len(o.Layout) == 0 {
				o.Layout = json.RawMessage(`[]`)
			}
			if len(o.Pictures) == 0 {
				o.Pictures = json.RawMessage(`[]`)
			}
			_ = json.NewEncoder(w).Encode(o)
		})

		r.Put("/outfits/{id}", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			idStr := chi.URLParam(req, "id")
			id, err := strconv.Atoi(idStr)
			if err != nil {
				http.Error(w, "bad id", http.StatusBadRequest)
				return
			}
			var body createOutfitBody
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if body.Name == "" {
				http.Error(w, "name required", http.StatusBadRequest)
				return
			}
			if body.ItemIDs == nil {
				body.ItemIDs = []int{}
			}
			if len(body.Extra) == 0 {
				body.Extra = json.RawMessage(`{}`)
			}
			if len(body.Layout) == 0 {
				body.Layout = json.RawMessage(`[]`)
			}
			if len(body.Pictures) == 0 {
				body.Pictures = json.RawMessage(`[]`)
			}
			wears := 0
			if body.Wears != nil {
				wears = *body.Wears
			}
			w.Header().Set("Content-Type", "application/json")

			if pool == nil {
				next := Outfit{ID: id, Name: body.Name, Wears: wears, ItemIDs: body.ItemIDs, CoverDataURL: body.CoverDataURL, Extra: body.Extra, Layout: body.Layout, Pictures: body.Pictures}
				if o, ok := mem.update(user, id, next); ok {
					_ = json.NewEncoder(w).Encode(o)
					return
				}
				http.NotFound(w, req)
				return
			}

			ctx := req.Context()
			if len(body.ItemIDs) > 0 {
				var n int
				err := pool.QueryRow(ctx, `
					SELECT COUNT(*) FROM items WHERE user_sub = $1 AND id = ANY($2::int[])`,
					user, body.ItemIDs).Scan(&n)
				if err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				if n != len(body.ItemIDs) {
					http.Error(w, "one or more item ids are invalid or belong to another user", http.StatusBadRequest)
					return
				}
			}

			tx, err := pool.Begin(ctx)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer tx.Rollback(ctx)

			tag, err := tx.Exec(ctx, `
				UPDATE outfits
				SET name = $1, wears = $2, cover_data_url = $3, extra = $4, layout = $5, pictures = $6
				WHERE id = $7 AND user_sub = $8`,
				body.Name, wears, body.CoverDataURL, body.Extra, body.Layout, body.Pictures, id, user,
			)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			if tag.RowsAffected() == 0 {
				http.NotFound(w, req)
				return
			}

			if _, err := tx.Exec(ctx, `DELETE FROM outfit_items WHERE outfit_id = $1`, id); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			for _, itemID := range body.ItemIDs {
				if _, err := tx.Exec(ctx, `INSERT INTO outfit_items (outfit_id, item_id) VALUES ($1, $2)`, id, itemID); err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
			}
			if err := tx.Commit(ctx); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}

			o := Outfit{ID: id, Name: body.Name, Wears: wears, ItemIDs: body.ItemIDs, CoverDataURL: body.CoverDataURL, Extra: body.Extra, Layout: body.Layout, Pictures: body.Pictures}
			_ = json.NewEncoder(w).Encode(o)
		})

		r.Delete("/outfits/{id}", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			idStr := chi.URLParam(req, "id")
			id, err := strconv.Atoi(idStr)
			if err != nil {
				http.Error(w, "bad id", http.StatusBadRequest)
				return
			}

			if pool == nil {
				if mem.delete(user, id) {
					w.WriteHeader(http.StatusNoContent)
					return
				}
				http.NotFound(w, req)
				return
			}

			ctx := req.Context()
			tag, err := pool.Exec(ctx, `DELETE FROM outfits WHERE id = $1 AND user_sub = $2`, id, user)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			if tag.RowsAffected() == 0 {
				http.NotFound(w, req)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		})
	})

	addr := ":8082"
	if v := os.Getenv("PORT"); v != "" {
		addr = ":" + v
	}
	log.Printf("outfits-service listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}
