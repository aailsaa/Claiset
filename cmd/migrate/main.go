package main

import (
	"context"
	"embed"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed schema.sql
var schemaFS embed.FS

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required (use the same value your microservices use for AWS RDS).")
	}
	sqlBytes, err := schemaFS.ReadFile("schema.sql")
	if err != nil {
		log.Fatalf("read schema: %v", err)
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer pool.Close()

	if _, err := pool.Exec(ctx, string(sqlBytes)); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	fmt.Println("migration applied OK")
}
