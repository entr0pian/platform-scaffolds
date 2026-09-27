suite: ServiceMonitor
templates:
  - templates/servicemonitor.yaml
  - templates/service.yaml
capabilities:
  apiVersions:
    - monitoring.coreos.com/v1
tests:
  - it: renders by default when the Prometheus Operator API is served
    template: templates/servicemonitor.yaml
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: ServiceMonitor
      - equal:
          path: apiVersion
          value: monitoring.coreos.com/v1
      - equal:
          path: metadata.name
          value: {{ componentName }}
      - notExists:
          path: metadata.namespace

  - it: selects the chart's Service by its own label
    template: templates/servicemonitor.yaml
    asserts:
      - equal:
          path: spec.selector.matchLabels
          value:
            app.kubernetes.io/name: {{ componentName }}
      - notExists:
          path: spec.namespaceSelector

  - it: the Service carries the selected label and a port named http
    template: templates/service.yaml
    asserts:
      - equal:
          path: metadata.labels["app.kubernetes.io/name"]
          value: {{ componentName }}
      - equal:
          path: spec.ports[0].name
          value: http

  - it: scrapes the http port at the default path and interval
    template: templates/servicemonitor.yaml
    asserts:
      - equal:
          path: spec.endpoints[0].port
          value: http
      - equal:
          path: spec.endpoints[0].path
          value: /metrics
      - equal:
          path: spec.endpoints[0].interval
          value: 30s

  - it: honours a configured path and interval
    template: templates/servicemonitor.yaml
    set:
      observability.metrics.path: /internal/metrics
      observability.metrics.interval: 15s
    asserts:
      - equal:
          path: spec.endpoints[0].path
          value: /internal/metrics
      - equal:
          path: spec.endpoints[0].interval
          value: 15s

  - it: maps platform identity labels to component and environment
    template: templates/servicemonitor.yaml
    set:
      platform.component: {{ componentName }}
      platform.environment: dev
    asserts:
      - contains:
          path: spec.endpoints[0].relabelings
          content:
            sourceLabels: [__meta_kubernetes_service_label_platform_taskapp_io_component]
            targetLabel: component
      - contains:
          path: spec.endpoints[0].relabelings
          content:
            sourceLabels: [__meta_kubernetes_service_label_platform_taskapp_io_environment]
            targetLabel: environment
      - equal:
          path: metadata.labels["platform.taskapp.io/component"]
          value: {{ componentName }}
      - equal:
          path: metadata.labels["platform.taskapp.io/environment"]
          value: dev

  - it: the Service carries the identity labels the relabelings read
    template: templates/service.yaml
    set:
      platform.component: {{ componentName }}
      platform.environment: dev
    asserts:
      - equal:
          path: metadata.labels["platform.taskapp.io/component"]
          value: {{ componentName }}
      - equal:
          path: metadata.labels["platform.taskapp.io/environment"]
          value: dev

  - it: is not rendered when metrics are disabled
    template: templates/servicemonitor.yaml
    set:
      observability.metrics.enabled: false
    asserts:
      - hasDocuments:
          count: 0

