// Package metrics owns the service's Prometheus instrumentation: the
// registry, the /metrics handler, HTTP request metrics and database pool
// metrics.
//
// It deliberately knows nothing about where the service runs. Platform
// identity (component, environment) is attached to every series by the
// chart's ServiceMonitor at scrape time, not by the application.
package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// NewRegistry returns a registry pre-loaded with the standard Go runtime
// (go_*) and process (process_*) collectors. A dedicated registry rather
// than prometheus.DefaultRegisterer keeps tests isolated and makes every
// exposed metric an explicit choice.
func NewRegistry() *prometheus.Registry {
	reg := prometheus.NewRegistry()
	reg.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)
	return reg
}

// Handler serves reg in the Prometheus exposition format.
func Handler(reg *prometheus.Registry) http.Handler {
	return promhttp.HandlerFor(reg, promhttp.HandlerOpts{Registry: reg})
}
