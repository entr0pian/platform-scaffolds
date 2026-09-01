package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	_ "github.com/lib/pq"
)

func main() {
	db := connectDB()
	if db != nil {
		defer db.Close()
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if db == nil {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("ok: database not configured"))
			return
		}
		if err := db.PingContext(r.Context()); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintf(w, "database unreachable: %v", err)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok: database reachable"))
	})

	log.Println("{{ componentName }} listening on :8080")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatal(err)
	}
}

// connectDB returns nil when DB_HOST is unset — the database capability is
// disabled (chart's database.enabled=false), not a connection failure.
// It does not ping at startup: a fresh pod shouldn't crash-loop waiting on a
// database that's still provisioning. /readyz is what actually checks
// reachability, on demand.
func connectDB() *sql.DB {
	host := os.Getenv("DB_HOST")
	if host == "" {
		return nil
	}

	sslmode := os.Getenv("DB_SSLMODE")
	if sslmode == "" {
		sslmode = "require"
	}
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host,
		os.Getenv("DB_PORT"),
		os.Getenv("DB_USER"),
		os.Getenv("DB_PASSWORD"),
		os.Getenv("DB_NAME"),
		sslmode,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Printf("database configured but failed to open: %v", err)
		return nil
	}
	return db
}
