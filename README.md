# platform-scaffolds

Source-of-truth repository for the platform's application scaffolds — the templates
used to generate the initial contents of a new component's repository.

```
scaffold.yaml + template/ + parameters → rendered application repository
```

This repo only defines *what a generated repository looks like*. It does not render
templates or create repositories itself — that's a future scaffolding executor's job
(see [Future integration](#future-integration-with-component-operator) below).

## Available scaffolds

| Scaffold | Path | Description |
|---|---|---|
| `golang-service` | `templates/golang-service` | Minimal Go HTTP service: server skeleton, Dockerfile, Helm chart (Deployment + Service), CI workflow with GHCR image push |

## Directory structure

```
platform-scaffolds/
├── README.md
└── templates/
    └── <scaffold-name>/
        ├── scaffold.yaml       # metadata + parameter contract
        └── template/           # files to render into the new repository
```

Each scaffold is self-contained: its own `scaffold.yaml` and `template/` directory.
Adding a new scaffold means adding a new `templates/<name>/` directory — nothing else
in this repo needs to change.

## Scaffold manifest (`scaffold.yaml`)

Each scaffold declares its identity, version, and the parameters it requires:

```yaml
name: golang-service
version: 0.1.0

parameters:
  componentName:
    type: string
    required: true

  repositoryName:
    type: string
    required: true

  owner:
    type: string
    required: true
```

`parameters` is the contract a caller (eventually `component-operator`, see below) must
satisfy to render the scaffold. `golang-service` currently requires:

| Parameter | Used for |
|---|---|
| `componentName` | Service/binary name, Helm chart name, Kubernetes resource names |
| `repositoryName` | Go module path (`github.com/{owner}/{repositoryName}`) |
| `owner` | GitHub org/user the generated repository belongs to; also used in the module path |

## Templating

Files under `template/` that need substitution carry a `.tpl` suffix and contain plain
`{{ parameterName }}` placeholders — e.g. `{{ componentName }}`, `{{ repositoryName }}`,
`{{ owner }}`. Files that don't need substitution (`Makefile`, `.gitignore`) are checked
in as-is, without the `.tpl` suffix and without placeholders.

This repo intentionally does not implement or depend on a specific rendering engine —
the placeholder syntax is simple enough for a renderer to satisfy with straight string
substitution, a text/template engine, or anything else a future scaffolding executor
chooses. `.tpl` → real filename (`go.mod.tpl` → `go.mod`) is the only other rule a
renderer needs to follow. A renderer only needs to replace the exact, known parameter
names (`componentName`, `repositoryName`, `owner`) — it must not try to parse or
evaluate every `{{ ... }}` it finds in a file.

That last point matters concretely for `chart/templates/*.yaml`, which contains
`{{ }}`-delimited syntax that belongs to a *different* engine and must survive scaffold
rendering untouched: `deployment.yaml` and `service.yaml` are plain Helm templates
(`{{ .Chart.Name }}`, `{{ .Values.image.repository }}`, ...), rendered by Helm at
install time, not by the scaffold renderer — so they're checked in without a `.tpl`
suffix and are never touched by scaffold rendering at all.

`.github/workflows/ci.yaml` avoids the same collision a different way: it's checked in
without a `.tpl` suffix and contains **no scaffold placeholders at all**. It derives
the image name entirely from GitHub Actions' own `github.repository` context
(`owner/repo`, lowercased) at workflow run time, rather than from `owner` /
`repositoryName` baked in at scaffold time — so it needs zero rendering and works
identically regardless of which account or org actually owns the generated repository.
`owner` is still a required scaffold parameter, but only for `go.mod.tpl`'s module path
and `values.yaml.tpl`'s default image repository — neither Go modules nor Helm have
access to GitHub Actions context, so those two genuinely need it substituted once at
scaffold time.

Example substitutions:

| Template | Rendered |
|---|---|
| `go.mod.tpl` | `module github.com/entr0pian/orders` |
| `README.md.tpl` | `# orders` |
| `chart/Chart.yaml.tpl` | `name: orders` |

## Versioning

Each scaffold is versioned independently, following [Semantic Versioning](https://semver.org/).
`golang-service` versions look like `0.1.0`, `0.2.0`, `1.0.0`, etc.

Versions are **not** separate directories — `main` always holds the latest scaffold
source, and Git history/tags preserve every released version.

Every release is an immutable Git tag of the form:

```
<scaffold-name>/v<version>
```

e.g. `golang-service/v0.1.0`. The `version` field in `templates/golang-service/scaffold.yaml`
at the time of tagging must equal `<version>` in the tag — this is enforced by
`.github/workflows/release.yaml`, which fails the tag's CI run if they don't match.

### Retrieving a specific scaffold version

```bash
git clone https://github.com/entr0pian/platform-scaffolds.git
cd platform-scaffolds
git checkout golang-service/v0.1.0
```

or, without a full clone:

```bash
git archive --remote=https://github.com/entr0pian/platform-scaffolds.git \
  golang-service/v0.1.0 templates/golang-service | tar -x
```

## Future integration with component-operator

Not implemented yet — this section records the intended shape so this repo's contract
(`scaffold.yaml` + `template/` + parameters, immutable version tags) stays compatible
with it.

```
Component CR
    ↓
component-operator          — decides WHEN and WHAT to scaffold
    ↓
GitHub XR
    ↓
Crossplane creates repository
    ↓
repository becomes Ready
    ↓
one-time scaffolding operation
    ↓
fetch platform-scaffolds version  — this repo: defines WHAT the generated repo looks like
    ↓
render template                   — scaffolding executor: performs the render + commit
    ↓
initial commit to new repository
```

Scaffolding is a **one-time bootstrap**, not continuous reconciliation: once the initial
commit lands, developers own the repository contents, and nothing here re-applies changes
to it later. A future `Component` spec is expected to select a scaffold and pinned version
like:

```yaml
spec:
  repository:
    name: orders
  scaffold:
    template: golang-service
    version: "0.1.0"
```

Whether the render/commit step lives inside `component-operator` or a separate executor
it delegates to is intentionally left open — this repo's job stops at defining the
scaffold contract.
