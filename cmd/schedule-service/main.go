package main

import (
	"context"
	"encoding/json"
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
	"github.com/jackc/pgx/v5/pgxpool"
)

type Assignment struct {
	ID       int    `json:"id"`
	OutfitID int    `json:"outfitId"`
	Day      string `json:"day"`
	Notes    string `json:"notes,omitempty"`
}

type createAssignmentBody struct {
	OutfitID int    `json:"outfitId"`
	Day      string `json:"day"`
	Notes    string `json:"notes"`
}

type memRow struct {
	Assignment
	UserSub string
}

type memSchedule struct {
	mu   sync.Mutex
	next int
	rows []memRow
}

func newMemSchedule() *memSchedule {
	return &memSchedule{rows: nil}
}

func (m *memSchedule) list(user, month string) []Assignment {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Assignment
	for _, r := range m.rows {
		if r.UserSub != user {
			continue
		}
		if month != "" && (len(r.Day) < 7 || r.Day[:7] != month) {
			continue
		}
		out = append(out, r.Assignment)
	}
	return out
}

func (m *memSchedule) upsert(user string, a Assignment) Assignment {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := range m.rows {
		if m.rows[i].UserSub == user && m.rows[i].Day == a.Day {
			m.rows[i].OutfitID = a.OutfitID
			m.rows[i].Notes = a.Notes
			return m.rows[i].Assignment
		}
	}
	m.next++
	a.ID = m.next
	m.rows = append(m.rows, memRow{Assignment: a, UserSub: user})
	return a
}

func (m *memSchedule) delete(user string, id int) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	var kept []memRow
	found := false
	for _, r := range m.rows {
		if r.ID == id && r.UserSub == user {
			found = true
			continue
		}
		kept = append(kept, r)
	}
	m.rows = kept
	return found
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	var pool *pgxpool.Pool
	if dsn != "" {
		ctx := context.Background()
		p, err := pgxpool.New(ctx, dsn)
		if err != nil {
			log.Fatalf("schedule-service: database: %v", err)
		}
		pool = p
		defer pool.Close()
		log.Println("schedule-service: using PostgreSQL (RDS / compose)")
	} else {
		log.Println("schedule-service: DATABASE_URL unset — using in-memory store (dev only)")
	}
	if os.Getenv("GOOGLE_CLIENT_ID") == "" {
		log.Println("schedule-service: GOOGLE_CLIENT_ID unset — Bearer token used as raw user id (dev only)")
	}

	mem := newMemSchedule()

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(func(next http.Handler) http.Handler { return httpserver.DevCORS(next) })

	r.Get("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"service": "schedule", "status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Use(auth.BearerMiddleware)

		r.Get("/assignments", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			month := req.URL.Query().Get("month")
			w.Header().Set("Content-Type", "application/json")
			if pool == nil {
				_ = json.NewEncoder(w).Encode(mem.list(user, month))
				return
			}
			ctx := req.Context()
			if month == "" {
				rows, err := pool.Query(ctx, `
					SELECT id, outfit_id, day::text, COALESCE(notes, '')
					FROM outfit_assignments WHERE user_sub = $1 ORDER BY day`, user)
				if err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				defer rows.Close()
				var list []Assignment
				for rows.Next() {
					var a Assignment
					if err := rows.Scan(&a.ID, &a.OutfitID, &a.Day, &a.Notes); err != nil {
						http.Error(w, err.Error(), http.StatusInternalServerError)
						return
					}
					list = append(list, a)
				}
				_ = json.NewEncoder(w).Encode(list)
				return
			}
			rows, err := pool.Query(ctx, `
				SELECT id, outfit_id, day::text, COALESCE(notes, '')
				FROM outfit_assignments
				WHERE user_sub = $1 AND to_char(day, 'YYYY-MM') = $2
				ORDER BY day`, user, month)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer rows.Close()
			var list []Assignment
			for rows.Next() {
				var a Assignment
				if err := rows.Scan(&a.ID, &a.OutfitID, &a.Day, &a.Notes); err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				list = append(list, a)
			}
			_ = json.NewEncoder(w).Encode(list)
		})

		r.Post("/assignments", func(w http.ResponseWriter, req *http.Request) {
			user, ok := auth.UserSub(req.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			var body createAssignmentBody
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				http.Error(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			if body.OutfitID <= 0 || body.Day == "" {
				http.Error(w, "outfitId and day (YYYY-MM-DD) required", http.StatusBadRequest)
				return
			}
			if _, err := time.Parse("2006-01-02", body.Day); err != nil {
				http.Error(w, "day must be YYYY-MM-DD", http.StatusBadRequest)
				return
			}
			w.Header().Set("Content-Type", "application/json")

			if pool == nil {
				a := mem.upsert(user, Assignment{OutfitID: body.OutfitID, Day: body.Day, Notes: body.Notes})
				w.WriteHeader(http.StatusCreated)
				_ = json.NewEncoder(w).Encode(a)
				return
			}

			ctx := req.Context()
			var outfitUser string
			err := pool.QueryRow(ctx, `SELECT user_sub FROM outfits WHERE id = $1`, body.OutfitID).Scan(&outfitUser)
			if err != nil || outfitUser != user {
				http.Error(w, "outfit not found", http.StatusBadRequest)
				return
			}

			var id int
			err = pool.QueryRow(ctx, `
				INSERT INTO outfit_assignments (user_sub, outfit_id, day, notes)
				VALUES ($1, $2, $3::date, NULLIF($4, ''))
				ON CONFLICT (user_sub, day) DO UPDATE SET outfit_id = EXCLUDED.outfit_id, notes = EXCLUDED.notes
				RETURNING id`,
				user, body.OutfitID, body.Day, body.Notes,
			).Scan(&id)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			a := Assignment{ID: id, OutfitID: body.OutfitID, Day: body.Day, Notes: body.Notes}
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(a)
		})

		r.Delete("/assignments/{id}", func(w http.ResponseWriter, req *http.Request) {
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
				if !mem.delete(user, id) {
					http.NotFound(w, req)
					return
				}
				w.WriteHeader(http.StatusNoContent)
				return
			}
			ctx := req.Context()
			tag, err := pool.Exec(ctx, `DELETE FROM outfit_assignments WHERE id = $1 AND user_sub = $2`, id, user)
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

	addr := ":8083"
	if v := os.Getenv("PORT"); v != "" {
		addr = ":" + v
	}
	log.Printf("schedule-service listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}
