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
	ID      int    `json:"id"`
	Name    string `json:"name"`
	Wears   int    `json:"wears"`
	ItemIDs []int  `json:"itemIds"`
}

type createOutfitBody struct {
	Name    string `json:"name"`
	ItemIDs []int  `json:"itemIds"`
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
				SELECT o.id, o.name, o.wears,
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
				if err := rows.Scan(&o.ID, &o.Name, &o.Wears, &raw); err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				if len(raw) > 0 {
					_ = json.Unmarshal(raw, &o.ItemIDs)
				}
				if o.ItemIDs == nil {
					o.ItemIDs = []int{}
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
			w.Header().Set("Content-Type", "application/json")

			if pool == nil {
				o := mem.add(user, Outfit{Name: body.Name, Wears: 0, ItemIDs: body.ItemIDs})
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
			if err := tx.QueryRow(ctx, `INSERT INTO outfits (user_sub, name, wears) VALUES ($1, $2, 0) RETURNING id`, user, body.Name).Scan(&id); err != nil {
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
			o := Outfit{ID: id, Name: body.Name, Wears: 0, ItemIDs: body.ItemIDs}
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
				SELECT o.id, o.name, o.wears,
					COALESCE(
						(SELECT json_agg(oi.item_id ORDER BY oi.item_id)
						 FROM outfit_items oi WHERE oi.outfit_id = o.id),
						'[]'::json
					) AS item_ids
				FROM outfits o WHERE o.id = $1 AND o.user_sub = $2`, id, user,
			).Scan(&o.ID, &o.Name, &o.Wears, &raw)
			if err != nil {
				http.NotFound(w, req)
				return
			}
			if len(raw) > 0 {
				_ = json.Unmarshal(raw, &o.ItemIDs)
			}
			_ = json.NewEncoder(w).Encode(o)
		})
	})

	addr := ":8082"
	if v := os.Getenv("PORT"); v != "" {
		addr = ":" + v
	}
	log.Printf("outfits-service listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}
