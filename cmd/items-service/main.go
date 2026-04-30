package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"OnlineCloset/internal/auth"
	"OnlineCloset/internal/httpserver"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Item struct {
	ID           int            `json:"id"`
	Name         string         `json:"name"`
	Colors       []string       `json:"colors"`
	Category     string         `json:"category"`
	Subcategory  string         `json:"subcategory"`
	Price        float64        `json:"price"`
	Wears        int            `json:"wears"`
	ItemDate     *time.Time     `json:"itemDate,omitempty"`
	CreatedAt    time.Time      `json:"createdAt"`
	PhotoDataURL *string        `json:"photoDataUrl,omitempty"`
	Extra        json.RawMessage `json:"extra,omitempty"`
	Archived     bool           `json:"archived"`
}

type createItemBody struct {
	Name        string     `json:"name"`
	Colors      []string   `json:"colors"`
	Category    string     `json:"category"`
	Subcategory string     `json:"subcategory"`
	Price       float64    `json:"price"`
	Wears       int        `json:"wears"`
	ItemDate    *time.Time `json:"itemDate"`
	PhotoDataURL *string   `json:"photoDataUrl"`
	Extra       json.RawMessage `json:"extra"`
	Archived    bool       `json:"archived"`
}

type memRow struct {
	Item
	UserSub string
}

type memStore struct {
	mu   sync.Mutex
	next int
	rows []memRow
}

func (m *memStore) delete(user string, id int) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, r := range m.rows {
		if r.UserSub == user && r.Item.ID == id {
			m.rows = append(m.rows[:i], m.rows[i+1:]...)
			return true
		}
	}
	return false
}

func (m *memStore) list(user string) []Item {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Item
	for _, r := range m.rows {
		if r.UserSub == user && !r.Item.Archived {
			out = append(out, r.Item)
		}
	}
	return out
}

func (m *memStore) add(user string, it Item) Item {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.next++
	it.ID = m.next
	m.rows = append(m.rows, memRow{Item: it, UserSub: user})
	return it
}

func (m *memStore) get(user string, id int) (Item, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.rows {
		if r.UserSub == user && r.Item.ID == id {
			return r.Item, true
		}
	}
	return Item{}, false
}

func (m *memStore) update(user string, id int, next Item) (Item, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, r := range m.rows {
		if r.UserSub == user && r.Item.ID == id {
			next.ID = id
			next.CreatedAt = r.Item.CreatedAt
			m.rows[i].Item = next
			return next, true
		}
	}
	return Item{}, false
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	var pool *pgxpool.Pool
	if dsn != "" {
		ctx := context.Background()
		p, err := pgxpool.New(ctx, dsn)
		if err != nil {
			log.Fatalf("items-service: database: %v", err)
		}
		pool = p
		defer pool.Close()
		log.Println("items-service: using PostgreSQL (RDS / compose)")
	} else {
		log.Println("items-service: DATABASE_URL unset — using in-memory store (dev only)")
	}
	if os.Getenv("GOOGLE_CLIENT_ID") == "" {
		log.Println("items-service: GOOGLE_CLIENT_ID unset — Bearer token used as raw user id (dev only)")
	}

	mem := &memStore{next: 0, rows: nil}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(func(next http.Handler) http.Handler { return httpserver.DevCORS(next) })

	r.Get("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"service": "items", "status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Use(auth.BearerMiddleware)

		r.Get("/items", func(w http.ResponseWriter, req *http.Request) {
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
				SELECT id, name, colors, category, subcategory, price, wears, item_date, created_at, photo_data_url, extra, archived
				FROM items WHERE user_sub = $1 AND archived = false ORDER BY id`, user)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer rows.Close()
			var list []Item
			for rows.Next() {
				var it Item
				var colorsRaw []byte
				var itemDate *time.Time
				var photo *string
				var extraRaw []byte
				if err := rows.Scan(&it.ID, &it.Name, &colorsRaw, &it.Category, &it.Subcategory, &it.Price, &it.Wears, &itemDate, &it.CreatedAt, &photo, &extraRaw, &it.Archived); err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				if len(colorsRaw) > 0 {
					_ = json.Unmarshal(colorsRaw, &it.Colors)
				}
				it.ItemDate = itemDate
				it.PhotoDataURL = photo
				if len(extraRaw) > 0 {
					it.Extra = extraRaw
				}
				list = append(list, it)
			}
			_ = json.NewEncoder(w).Encode(list)
		})

		r.Post("/items", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			var body createItemBody
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if body.Name == "" {
				http.Error(w, "name required", http.StatusBadRequest)
				return
			}
			if body.Colors == nil {
				body.Colors = []string{}
			}
			if len(body.Extra) == 0 {
				body.Extra = json.RawMessage(`{}`)
			}
			w.Header().Set("Content-Type", "application/json")

			if pool == nil {
				now := time.Now().UTC()
				it := mem.add(user, Item{
					Name: body.Name, Colors: body.Colors, Category: body.Category,
					Subcategory: body.Subcategory, Price: body.Price, Wears: body.Wears, ItemDate: body.ItemDate, CreatedAt: now, PhotoDataURL: body.PhotoDataURL, Extra: body.Extra, Archived: body.Archived,
				})
				w.WriteHeader(http.StatusCreated)
				_ = json.NewEncoder(w).Encode(it)
				return
			}

			colorsJSON, err := json.Marshal(body.Colors)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			ctx := req.Context()
			var id int
			var createdAt time.Time
			err = pool.QueryRow(ctx, `
				INSERT INTO items (user_sub, name, colors, category, subcategory, price, wears, item_date, photo_data_url, extra, archived)
				VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $8, $9, $10::jsonb, $11)
				RETURNING id, created_at`,
				user, body.Name, colorsJSON, body.Category, body.Subcategory, body.Price, body.Wears, body.ItemDate, body.PhotoDataURL,
				body.Extra,
				body.Archived,
			).Scan(&id, &createdAt)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			it := Item{
				ID: id, Name: body.Name, Colors: body.Colors, Category: body.Category,
				Subcategory: body.Subcategory, Price: body.Price, Wears: body.Wears, ItemDate: body.ItemDate, CreatedAt: createdAt, PhotoDataURL: body.PhotoDataURL, Extra: body.Extra, Archived: body.Archived,
			}
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(it)
		})

		r.Get("/items/{id}", func(w http.ResponseWriter, req *http.Request) {
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
				if it, ok := mem.get(user, id); ok {
					_ = json.NewEncoder(w).Encode(it)
					return
				}
				http.NotFound(w, req)
				return
			}
			ctx := req.Context()
			var it Item
			var colorsRaw []byte
			var itemDate *time.Time
			var photo *string
			var extraRaw []byte
			err = pool.QueryRow(ctx, `
				SELECT id, name, colors, category, subcategory, price, wears, item_date, created_at, photo_data_url, extra, archived
				FROM items WHERE id = $1 AND user_sub = $2`, id, user,
			).Scan(&it.ID, &it.Name, &colorsRaw, &it.Category, &it.Subcategory, &it.Price, &it.Wears, &itemDate, &it.CreatedAt, &photo, &extraRaw, &it.Archived)
			if err != nil {
				http.NotFound(w, req)
				return
			}
			if len(colorsRaw) > 0 {
				_ = json.Unmarshal(colorsRaw, &it.Colors)
			}
			it.ItemDate = itemDate
			it.PhotoDataURL = photo
			if len(extraRaw) > 0 {
				it.Extra = extraRaw
			}
			_ = json.NewEncoder(w).Encode(it)
		})

		r.Put("/items/{id}", func(w http.ResponseWriter, req *http.Request) {
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
			var body createItemBody
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if body.Name == "" {
				http.Error(w, "name required", http.StatusBadRequest)
				return
			}
			if body.Colors == nil {
				body.Colors = []string{}
			}
			if len(body.Extra) == 0 {
				body.Extra = json.RawMessage(`{}`)
			}
			w.Header().Set("Content-Type", "application/json")

			if pool == nil {
				next := Item{
					ID: id, Name: body.Name, Colors: body.Colors, Category: body.Category,
					Subcategory: body.Subcategory, Price: body.Price, Wears: body.Wears, ItemDate: body.ItemDate, PhotoDataURL: body.PhotoDataURL, Extra: body.Extra, Archived: body.Archived,
				}
				if it, ok := mem.update(user, id, next); ok {
					_ = json.NewEncoder(w).Encode(it)
					return
				}
				http.NotFound(w, req)
				return
			}

			colorsJSON, err := json.Marshal(body.Colors)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			ctx := req.Context()
			var createdAt time.Time
			err = pool.QueryRow(ctx, `
				UPDATE items
				SET name = $1, colors = $2::jsonb, category = $3, subcategory = $4, price = $5, wears = $6, item_date = $7, photo_data_url = $8, extra = $9::jsonb, archived = $10
				WHERE id = $11 AND user_sub = $12
				RETURNING created_at`,
				body.Name, colorsJSON, body.Category, body.Subcategory, body.Price, body.Wears, body.ItemDate, body.PhotoDataURL, body.Extra,
				body.Archived, id, user,
			).Scan(&createdAt)
			if err != nil {
				if errors.Is(err, pgx.ErrNoRows) {
					http.NotFound(w, req)
					return
				}
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			it := Item{
				ID: id, Name: body.Name, Colors: body.Colors, Category: body.Category,
				Subcategory: body.Subcategory, Price: body.Price, Wears: body.Wears, ItemDate: body.ItemDate, CreatedAt: createdAt, PhotoDataURL: body.PhotoDataURL, Extra: body.Extra, Archived: body.Archived,
			}
			_ = json.NewEncoder(w).Encode(it)
		})

		r.Delete("/items/{id}", func(w http.ResponseWriter, req *http.Request) {
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
			cmd, err := pool.Exec(ctx, `DELETE FROM items WHERE id = $1 AND user_sub = $2`, id, user)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			if cmd.RowsAffected() == 0 {
				http.NotFound(w, req)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		})
	})

	addr := ":8081"
	if v := os.Getenv("PORT"); v != "" {
		addr = ":" + v
	}
	log.Printf("items-service listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}
