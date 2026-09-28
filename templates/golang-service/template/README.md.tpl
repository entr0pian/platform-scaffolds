# {{ componentName }}

Generated from the `golang-service` scaffold in [platform-scaffolds](https://github.com/entr0pian/platform-scaffolds).

## Development

```
make build
make test
make run
```

## Endpoints

- `GET /` — index: JSON with the service name and the endpoints below. It reads
  from the `endpoints` list in `cmd/server/main.go`; add to that list whenever you
  register a route.
- `GET /healthz` — liveness; always `200`, no dependencies checked.
- `GET /readyz` — readiness; `200` if the database is unconfigured or reachable,
  `503` if `bindings.database` is set but the database can't be reached.
- `GET /metrics` — Prometheus metrics (see below).

## Metrics

`/metrics` serves, in the Prometheus text format:

| Metric | Source |
|---|---|
| `go_*` | Go runtime: goroutines, memory, GC |
| `process_*` | Process CPU, memory, file descriptors |
| `http_requests_total{method,route,status}` | Every request except `/healthz`, `/readyz`, `/metrics` |
| `http_request_duration_seconds{method,route,status}` | Histogram, same requests |
| `go_sql_*{db_name="database"}` | Connection pool (`db.Stats()`), only when a database binding is mounted |

Instrumentation lives in `internal/metrics`. The HTTP middleware wraps the
`http.ServeMux` in `cmd/server/main.go`, and `route` is the **pattern the mux
matched**, not the request path: register `GET /orders/{id}` and every order
lands under `route="/orders/{id}"`. Requests matching no pattern (404/405) share
`route="unmatched"`, and non-standard methods become `method="OTHER"`, so no
client can create unbounded series. Keep it that way: register routes on the mux
with `{wildcards}`, and don't add labels carrying IDs, IPs or raw paths.

Kubernetes-level metrics (pod CPU/memory, restarts, replicas) aren't exposed
here. They come from the cluster's own monitoring stack.

## Deployment

Helm chart lives in `chart/`. It sets CPU/memory requests and limits by
default (`resources` in `values.yaml`); tune them to the service's real usage,
but keep limits set: the platform's utilization metrics divide usage by the
container's limit, so a container without one has no utilization percentage.

`helm unittest chart` `helm unittest chart` runs its tests
([helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin).

With `observability.metrics.enabled` (default `true`), the chart adds a
`ServiceMonitor` for the Service's `http` port, but only when the cluster serves
the Prometheus Operator API (`monitoring.coreos.com/v1`), so the chart still
installs on clusters without it. The ServiceMonitor maps the Service's
`platform.taskapp.io/{component,environment}` labels to `component` and
`environment` on every series, so metrics can be queried as
`http_requests_total{component="{{ componentName }}", environment="dev"}`. The
platform sets those labels at deploy time; the application never sees them.

**Prometheus selector assumption.** The ServiceMonitor carries no
Prometheus-specific selector label (such as `release: <name>`). Prometheus must be
configured to select ServiceMonitors in any namespace, e.g. for
kube-prometheus-stack:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # serviceMonitorSelector: {}
    serviceMonitorNamespaceSelector: {}
```
