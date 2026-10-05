suite: PodDisruptionBudget
templates:
  - templates/poddisruptionbudget.yaml
tests:
  - it: allows one voluntary eviction at a time, selecting the Deployment's pods
    asserts:
      - isKind:
          of: PodDisruptionBudget
      - equal:
          path: spec.maxUnavailable
          value: 1
      - equal:
          path: spec.selector.matchLabels
          value:
            app.kubernetes.io/name: {{ componentName }}

  - it: is not rendered when disabled
    set:
      podDisruptionBudget.enabled: false
    asserts:
      - hasDocuments:
          count: 0
