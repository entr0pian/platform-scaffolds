package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

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

// connectDB returns nil when the database binding isn't mounted — the
// database capability is disabled (chart's bindings.database absent), not a
// connection failure. It does not ping at startup: a fresh pod shouldn't
// crash-loop waiting on a database that's still provisioning. /readyz is
// what actually checks reachability, on demand.
func connectDB() *sql.DB {
	root := os.Getenv("SERVICE_BINDING_ROOT")
	if root == "" {
		root = "/bindings"
	}
	dir := filepath.Join(root, "database")

	host, err := readBindingFile(dir, "endpoint")
	if err != nil {
		return nil
	}

	sslmode := os.Getenv("DB_SSLMODE")
	if sslmode == "" {
		sslmode = "require"
	}
	port, _ := readBindingFile(dir, "port")
	user, _ := readBindingFile(dir, "username")
	password, _ := readBindingFile(dir, "password")
	name, _ := readBindingFile(dir, "dbname")

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port, user, password, name, sslmode,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Printf("database configured but failed to open: %v", err)
		return nil
	}
	return db
}

// readBindingFile reads one key from a mounted binding directory, per the
// $SERVICE_BINDING_ROOT/<binding>/<key> file convention.
func readBindingFile(dir, name string) (string, error) {
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}
