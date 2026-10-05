suite: Ingress
templates:
  - templates/ingress.yaml
tests:
  - it: publishes <component>.<environment>.<domain> on the environment's shared ALB
    set:
      platform.component: {{ componentName }}
      platform.environment: dev
    asserts:
      - isKind:
          of: Ingress
      - equal:
          path: spec.rules[0].host
          value: {{ componentName }}.dev.gerodimos.dev
      - equal:
          path: spec.ingressClassName
          value: alb
      - equal:
          path: metadata.annotations["alb.ingress.kubernetes.io/group.name"]
          value: dev
      - equal:
          path: metadata.annotations["alb.ingress.kubernetes.io/scheme"]
          value: internet-facing
      - equal:
          path: spec.rules[0].http.paths[1].backend.service
          value:
            name: {{ componentName }}
            port:
              name: http

  - it: answers /metrics with a 404 at the ALB, ahead of the catch-all
    set:
      platform.component: {{ componentName }}
      platform.environment: dev
    asserts:
      - equal:
          path: spec.rules[0].http.paths[0]
          value:
            path: /metrics
            pathType: Exact
            backend:
              service:
                name: metrics-not-found
                port:
                  name: use-annotation
      - matchRegex:
          path: metadata.annotations["alb.ingress.kubernetes.io/actions.metrics-not-found"]
          pattern: '"statusCode":"404"'

  - it: takes the domain and extra annotations from values
    set:
      platform.component: {{ componentName }}
      platform.environment: prod
      platform.domain: example.com
      ingress.annotations:
        alb.ingress.kubernetes.io/group.name: custom
    asserts:
      - equal:
          path: spec.rules[0].host
          value: {{ componentName }}.prod.example.com
      - equal:
          path: metadata.annotations["alb.ingress.kubernetes.io/group.name"]
          value: custom

  - it: is not rendered outside the platform
    asserts:
      - hasDocuments:
          count: 0

  - it: is not rendered in an environment the certificate doesn't cover
    set:
      platform.component: {{ componentName }}
      platform.environment: management
    asserts:
      - hasDocuments:
          count: 0

  - it: is not rendered when disabled
    set:
      platform.component: {{ componentName }}
      platform.environment: dev
      ingress.enabled: false
    asserts:
      - hasDocuments:
          count: 0
