package metrics

import (
	"database/sql"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

// dbLabel is the value of the collector's db_name label: the binding's name,
// not the real database name, so nothing about the database's identity or
// credentials leaks into metrics.
const dbLabel = "database"

// RegisterDB exposes db's connection pool statistics (db.Stats()) as the
// client library's standard go_sql_* metrics: open/in-use/idle connections,
// wait count and total wait time, and connections closed by pool limits.
// A nil db — no database binding mounted — registers nothing.
func RegisterDB(reg prometheus.Registerer, db *sql.DB) {
	if db == nil {
		return
	}
	reg.MustRegister(collectors.NewDBStatsCollector(db, dbLabel))
}
