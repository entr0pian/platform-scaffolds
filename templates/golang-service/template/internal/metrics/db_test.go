package metrics

import (
	"database/sql"
	"strings"
	"testing"

	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
)

func TestRegisterDBNilIsNoop(t *testing.T) {
	reg := prometheus.NewRegistry()

	RegisterDB(reg, nil)

	if out := gatherText(t, reg); strings.Contains(out, "go_sql_") {
		t.Fatalf("nil db exposed pool metrics:\n%s", out)
	}
}

// sql.Open never connects, so pool stats are collectable without a
// running PostgreSQL.
func TestRegisterDBExposesPoolStats(t *testing.T) {
	db, err := sql.Open("postgres", "host=db.internal.example port=5432 user=app password=s3cret dbname=orders sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	reg := prometheus.NewRegistry()

	RegisterDB(reg, db)

	out := gatherText(t, reg)
	for _, want := range []string{
		`go_sql_open_connections{db_name="database"} 0`,
		`go_sql_in_use_connections{db_name="database"} 0`,
		`go_sql_idle_connections{db_name="database"} 0`,
		`go_sql_wait_count_total{db_name="database"} 0`,
		`go_sql_wait_duration_seconds_total{db_name="database"} 0`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q", want)
		}
	}
	for _, secret := range []string{"db.internal.example", "app", "s3cret", "orders"} {
		if strings.Contains(out, `"`+secret+`"`) {
			t.Errorf("connection detail %q leaked into a label", secret)
		}
	}
}
