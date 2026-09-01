# {{ componentName }}

Generated from the `golang-service` scaffold in [platform-scaffolds](https://github.com/entr0pian/platform-scaffolds).

## Development

```
make build
make test
make run
```

## Endpoints

- `GET /healthz` — liveness; always `200`, no dependencies checked.
- `GET /readyz` — readiness; `200` if the database is unconfigured or reachable,
  `503` if `database.enabled` is on but the database can't be reached.

## Deployment

Helm chart lives in `chart/`.
