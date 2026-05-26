# Platz.io

[Platz](https://platz.io) is a self-hosted control plane for Helm deployments. It turns your Helm charts into a guided, role-controlled experience — every team gets a typed form, a live status view, and an audit trail, without needing direct `kubectl` or `helm` access.

This chart installs Platz into a single Kubernetes namespace. It deploys the API, the web frontend, and the four background workers that make up a Platz installation (`k8s-agent`, `chart-discovery`, `resource-sync`, `status-updates`).

## TL;DR

```bash
helm repo add platzio https://platzio.github.io/helm-charts
helm repo update

kubectl create namespace platzio

kubectl -n platzio create secret generic postgres-creds \
  --from-literal=PGHOST=db.example.com \
  --from-literal=PGPORT=5432 \
  --from-literal=PGUSER=platz \
  --from-literal=PGPASSWORD='change-me' \
  --from-literal=PGDATABASE=platz

kubectl -n platzio create secret generic oidc-config \
  --from-literal=serverUrl=https://auth.example.com/realms/platz \
  --from-literal=clientId=platz \
  --from-literal=clientSecret='change-me'

helm install platz platzio/platzio -n platzio -f values.yaml
```

A full walk-through (including ingress, cert-manager, and OIDC setup) lives in the [Installing with Helm](https://platz.io/docs/guide/install/helm) guide.

## Introduction

Platz is built around a small set of concepts:

| Concept             | What it is                                                                                          |
| ------------------- | --------------------------------------------------------------------------------------------------- |
| **Env**             | A logical grouping of clusters and the deployments that run on them. Roles are assigned per env.    |
| **Cluster**         | A Kubernetes cluster registered with Platz. Attached to at most one env.                            |
| **Deployment Kind** | A category of deployments — usually one per service.                                                |
| **Deployment**      | A single Helm release Platz manages. Lives in its own namespace inside a cluster.                   |
| **Helm Registry**   | An OCI registry (ECR or generic) that Platz scans for charts.                                       |
| **Chart Extension** | Optional YAML files that ship inside a Helm chart and give Platz richer inputs, outputs, and forms. |
| **Task**            | A unit of work against a deployment — install, upgrade, action invocation, resource restart.        |

The chart deploys the following workloads:

- **api** — HTTP + WebSocket API consumed by the frontend, bots, and CI.
- **frontend** — nginx serving the SPA.
- **k8s-agent** — one StatefulSet per `k8sAgent.instances[]` entry. Picks up deployment tasks and runs `helm install` / `helm upgrade` inside a target cluster.
- **chart-discovery** — one StatefulSet per `chartDiscovery.instances[]` entry. Watches a Helm OCI registry (ECR via SQS, or any generic OCI registry via polling).
- **resource-sync** — reflects Kubernetes resource state of every Platz-managed namespace into the database.
- **status-updates** — polls deployment status endpoints exposed by charts that opt in to the Status feature.

## Prerequisites

- **Kubernetes 1.14+** (the chart emits `networking.k8s.io/v1` Ingress resources).
- **Helm 3.8+** (older versions lack OCI registry support, which Platz relies on for chart discovery).
- **PostgreSQL 15+** reachable from the cluster — RDS, Aurora, Cloud SQL, or self-managed. Platz is built and tested against PostgreSQL 17.
- **An OIDC provider** for user authentication (Auth0, Keycloak, Dex, Google, Okta, GitHub via an OIDC bridge — anything that speaks OpenID Connect).
- **At least one Helm OCI registry** that Platz can scan for charts. Amazon ECR and any registry that implements the OCI Distribution Spec are both supported.
- **An ingress controller** (`ingress-nginx`, AWS Load Balancer Controller, Traefik, …) in the cluster where Platz runs, if you plan to expose it through Ingress.
- **`cert-manager`** (optional) if you want the chart to issue a TLS certificate for you.

## Installing the Chart

### 1. Add the repository

```bash
helm repo add platzio https://platzio.github.io/helm-charts
helm repo update
```

### 2. Create the namespace and secrets

Platz reads database and OIDC credentials from two pre-existing Kubernetes secrets. The chart never bundles or generates them.

**Database credentials** (default secret name: `postgres-creds`, configurable via `database.secretName`):

| Key          | Example         | Notes                                            |
| ------------ | --------------- | ------------------------------------------------ |
| `PGHOST`     | `db.example.com` | Hostname only. No port, no `postgres://` prefix. |
| `PGPORT`     | `5432`          | Standard libpq env var.                          |
| `PGUSER`     | `platz`         | DB user with full privileges on the database.    |
| `PGPASSWORD` | `your-password` | Stored as-is in the secret.                      |
| `PGDATABASE` | `platz`         | The database name. Platz writes its tables here. |

**OIDC client credentials** (default secret name: `oidc-config`):

| Key            | Example                                 | Notes                |
| -------------- | --------------------------------------- | -------------------- |
| `serverUrl`    | `https://auth.example.com/realms/platz` | OIDC issuer URL.     |
| `clientId`     | `platz`                                 | OAuth 2.0 client ID. |
| `clientSecret` | `your-secret`                           | OAuth 2.0 secret.    |

When configuring the OIDC application in your IdP, set the redirect URI to `https://<your-platz-host>/auth/google/callback`. The `/google/` segment is historical — the same callback path is used regardless of provider.

### 3. Install

```bash
helm install platz platzio/platzio \
  --namespace platzio \
  --values platz-values.yaml \
  --wait
```

A minimal `platz-values.yaml` looks like this:

```yaml
auth:
  adminEmails:
    - admin@example.com

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  rules:
    - host: platz.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - platz.example.com
      secretName: platz-tls

k8sAgent:
  instances:
    - name: this-cluster
      provider: local

chartDiscovery:
  instances:
    - name: default
      provider: oci
      oci:
        registryUrl: https://registry.example.com
        pollInterval: 30s
```

## Uninstalling the Chart

```bash
helm uninstall platz -n platzio
```

This removes the workloads, services, ingress, ServiceAccounts, and (if created) the cert-manager Certificate and Issuer. It does **not** delete:

- The `postgres-creds` and `oidc-config` secrets you created yourself.
- The PostgreSQL database. Platz's data — envs, deployments, tasks, audit history — lives there. Drop the database manually if you want a clean slate.
- The namespaces of any deployments Platz managed inside target clusters.

## Parameters

### Images

| Name                          | Description                                       | Default              |
| ----------------------------- | ------------------------------------------------- | -------------------- |
| `images.backend.repository`   | Backend (API + workers) image repository          | `platzio/backend`    |
| `images.backend.tag`          | Backend image tag                                 | Chart `appVersion`   |
| `images.backend.pullPolicy`   | Backend image pull policy                         | `IfNotPresent`       |
| `images.frontend.repository`  | Frontend image repository                         | `platzio/frontend`   |
| `images.frontend.tag`         | Frontend image tag                                | Chart `appVersion`   |
| `images.frontend.pullPolicy`  | Frontend image pull policy                        | `IfNotPresent`       |
| `images.helm.repository`      | Helm worker base image (used by k8s-agent runner) | `platzio/base`       |
| `images.helm.tag`             | Helm worker base image tag                        | `v9`                 |
| `imagePullSecrets`            | List of imagePullSecrets to attach to pods        | `[]`                 |

### Auth

| Name                                                  | Description                                                                                | Default                                                  |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| `auth.adminEmails`                                    | Emails that should be promoted to site admin on first login                                | `[]`                                                     |
| `auth.oidc.serverUrl.valueFrom.secretKeyRef`          | Secret key holding the OIDC issuer URL                                                     | `oidc-config` / `serverUrl`                              |
| `auth.oidc.clientId.valueFrom.secretKeyRef`           | Secret key holding the OIDC client ID                                                      | `oidc-config` / `clientId`                               |
| `auth.oidc.clientSecret.valueFrom.secretKeyRef`       | Secret key holding the OIDC client secret                                                  | `oidc-config` / `clientSecret`                           |

### Database

| Name                                       | Description                                                                                                  | Default          |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------ | ---------------- |
| `database.secretName`                      | Name of the Kubernetes Secret holding `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`               | `postgres-creds` |
| `database.pool.maxSize`                    | Maximum number of database connections per pod (`DB_POOL_MAX_SIZE`)                                          | `""` (50)        |
| `database.pool.minIdle`                    | Minimum idle connections to keep in the pool (`DB_POOL_MIN_IDLE`)                                            | `""`             |
| `database.pool.connectionTimeoutSecs`      | Seconds to wait for a connection before erroring (`DB_POOL_CONNECTION_TIMEOUT_SECS`)                         | `""` (30)        |
| `database.pool.idleTimeoutSecs`            | Idle connection timeout in seconds (`DB_POOL_IDLE_TIMEOUT_SECS`)                                             | `""` (600)       |
| `database.pool.maxLifetimeSecs`            | Maximum lifetime of a connection in seconds (`DB_POOL_MAX_LIFETIME_SECS`)                                    | `""` (1800)      |

Empty pool values fall back to the binary's built-in defaults shown above.

### API

| Name                          | Description                                                          | Default      |
| ----------------------------- | -------------------------------------------------------------------- | ------------ |
| `api.replicaCount`            | Replicas of the API deployment                                       | `1`          |
| `api.resources`               | CPU/memory requests and limits for the API container                 | See `values.yaml` |
| `api.serviceAccount.name`     | ServiceAccount name for the API                                      | `platz-api`  |
| `api.serviceAccount.annotations` | Extra annotations on the API ServiceAccount                       | `{}`         |
| `api.service.type`            | Service type for the API                                             | `ClusterIP`  |
| `api.service.port`            | Service port for the API                                             | `80`         |
| `api.service.containerPort`   | Container port for the API                                           | `3000`       |
| `api.extraEnv`                | Extra environment variables for the API container (`EnvVar[]`)       | `[]`         |

### Frontend

| Name                              | Description                                                | Default            |
| --------------------------------- | ---------------------------------------------------------- | ------------------ |
| `frontend.replicaCount`           | Replicas of the frontend deployment                        | `1`                |
| `frontend.resources`              | CPU/memory requests and limits for the frontend container  | See `values.yaml`  |
| `frontend.serviceAccount.name`    | ServiceAccount for the frontend                            | `platz-frontend`   |
| `frontend.serviceAccount.annotations` | Extra annotations on the frontend ServiceAccount       | `{}`               |
| `frontend.service.type`           | Service type for the frontend                              | `ClusterIP`        |
| `frontend.service.port`           | Service port for the frontend                              | `80`               |
| `frontend.service.containerPort`  | Container port for the frontend                            | `80`               |

### k8s-agent

`k8sAgent.instances[]` is a list — one entry per Platz "agent". Most installs run a single instance; multi-cluster setups can run several so that each cluster has its own credentials.

| Name                                                              | Description                                                                                                                                       | Default     |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `k8sAgent.instances[].name`                                       | Logical name of the agent instance (used in resource names)                                                                                       | `default`   |
| `k8sAgent.instances[].provider`                                   | Cluster discovery mode: `eks` (scan AWS via IAM) or `local` (register a single cluster from a kubeconfig context)                                 | `eks`       |
| `k8sAgent.instances[].localContext`                               | When `provider=local`, the kubeconfig context to register. Empty falls back to the kubeconfig's current-context.                                  | `""`        |
| `k8sAgent.instances[].localKubeconfig`                            | When `provider=local`, optional path to a kubeconfig file inside the pod. Empty uses the kubectl default.                                         | `""`        |
| `k8sAgent.instances[].disableDeploymentCredentials`               | When `true`, the agent skips provisioning per-deployment credentials. Useful for local/dev setups with ambient credentials.                       | `false`     |
| `k8sAgent.instances[].deploymentCredentialsRefreshInterval`       | How often the agent rotates per-deployment credentials. Humantime duration (`20m`, `1h`). Empty falls back to the binary default (`20m`).        | `""`        |
| `k8sAgent.instances[].deploymentCredentialsTokenDuration`         | Lifetime of issued credential tokens. Humantime duration. Empty falls back to the binary default (`1h`).                                          | `""`        |
| `k8sAgent.instances[].serviceAccount.name`                        | ServiceAccount name for this agent instance. Empty auto-generates one.                                                                            | `""`        |
| `k8sAgent.instances[].serviceAccount.annotations`                 | Annotations on the agent's ServiceAccount (e.g. IRSA role ARN)                                                                                    | `{}`        |
| `k8sAgent.instances[].extraEnv`                                   | Extra environment variables for this agent instance (`EnvVar[]`)                                                                                  | `[]`        |
| `k8sAgent.resources`                                              | CPU/memory requests and limits for k8s-agent pods                                                                                                 | See `values.yaml` |

### chart-discovery

`chartDiscovery.instances[]` is a list — one entry per registry to watch.

| Name                                                | Description                                                                                                                                       | Default     |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `chartDiscovery.instances[].name`                   | Logical name of the discovery instance                                                                                                            | `default`   |
| `chartDiscovery.instances[].enableTagParser`        | When `true`, parse semantic information out of chart tags for richer UI grouping                                                                  | `false`     |
| `chartDiscovery.instances[].provider`               | Discovery backend: `ecr` (watch SQS for ECR push events) or `oci` (poll a generic OCI registry)                                                   | `ecr`       |
| `chartDiscovery.instances[].ecrEvents.queueName`    | SQS queue name to consume ECR image push events from (provider=ecr)                                                                               | `""`        |
| `chartDiscovery.instances[].ecrEvents.regionName`   | AWS region the SQS queue lives in (provider=ecr)                                                                                                  | `""`        |
| `chartDiscovery.instances[].oci.registryUrl`        | Base URL of the OCI registry to poll (provider=oci), e.g. `https://registry.example.com`                                                          | `""`        |
| `chartDiscovery.instances[].oci.pollInterval`       | Polling interval as a humantime duration (provider=oci)                                                                                           | `5s`        |
| `chartDiscovery.instances[].serviceAccount.name`    | ServiceAccount for this discovery instance                                                                                                        | `""`        |
| `chartDiscovery.instances[].serviceAccount.annotations` | Annotations on the discovery ServiceAccount (IRSA, etc.)                                                                                      | `{}`        |
| `chartDiscovery.instances[].extraEnv`               | Extra environment variables for this discovery instance (`EnvVar[]`)                                                                              | `[]`        |
| `chartDiscovery.resources`                          | CPU/memory requests and limits for chart-discovery pods                                                                                           | See `values.yaml` |

### resource-sync and status-updates

| Name                                | Description                                                          | Default                   |
| ----------------------------------- | -------------------------------------------------------------------- | ------------------------- |
| `resourceSync.replicaCount`         | Replicas of the resource-sync deployment                             | `1`                       |
| `resourceSync.resources`            | CPU/memory requests and limits for resource-sync                     | See `values.yaml`         |
| `resourceSync.serviceAccount.name`  | ServiceAccount for resource-sync                                     | `platz-resource-sync`     |
| `resourceSync.serviceAccount.annotations` | Annotations on the resource-sync ServiceAccount                | `{}`                      |
| `resourceSync.extraEnv`             | Extra environment variables for resource-sync (`EnvVar[]`)           | `[]`                      |
| `statusUpdates.replicaCount`        | Replicas of the status-updates deployment                            | `1`                       |
| `statusUpdates.resources`           | CPU/memory requests and limits for status-updates                    | See `values.yaml`         |
| `statusUpdates.serviceAccount.name` | ServiceAccount for status-updates                                    | `platz-status-updates`    |
| `statusUpdates.serviceAccount.annotations` | Annotations on the status-updates ServiceAccount              | `{}`                      |
| `statusUpdates.extraEnv`            | Extra environment variables for status-updates (`EnvVar[]`)          | `[]`                      |

### Ingress and TLS

| Name                          | Description                                                                                          | Default    |
| ----------------------------- | ---------------------------------------------------------------------------------------------------- | ---------- |
| `ingress.enabled`             | Create an Ingress for the frontend and API                                                           | `false`    |
| `ingress.className`           | `ingressClassName` value (`nginx`, `alb`, …)                                                         | `""`       |
| `ingress.annotations`         | Annotations on the Ingress (cert-manager issuer, AWS LB controller hints, etc.)                      | `{}`       |
| `ingress.rules`               | List of `{host, paths: [{path, pathType}]}` entries                                                  | See `values.yaml` |
| `ingress.tls`                 | Standard Ingress TLS spec — `[{hosts: [...], secretName: ...}]`                                     | `[]`       |
| `certManager.certificate.create` | Create a cert-manager `Certificate` resource alongside the ingress                                | `false`    |
| `certManager.issuer.create`   | Create a cert-manager `Issuer` resource                                                              | `false`    |
| `certManager.issuer.name`     | Name of the issuer to use (or create)                                                                | `""`       |
| `certManager.issuer.email`    | Contact email for ACME issuers                                                                       | `""`       |
| `certManager.issuer.kind`     | Issuer kind: `Issuer` or `ClusterIssuer`                                                             | `Issuer`   |
| `certManager.issuer.group`    | API group of the issuer                                                                              | `cert-manager.io` |
| `ownUrlOverride`              | External URL Platz uses for OIDC callbacks and Status URLs. Set this when not using ingress.        | `""`       |

### Backup CronJob

A self-contained CronJob can periodically dump Postgres to S3.

| Name                                                                       | Description                                                              | Default                  |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------ |
| `backupJob.enabled`                                                        | Create the backup CronJob                                                | `false`                  |
| `backupJob.config.bucketName`                                              | S3 bucket name to write dumps to                                         | `""`                     |
| `backupJob.config.bucketRegion`                                            | S3 bucket region                                                         | `""`                     |
| `backupJob.config.bucketPrefix`                                            | Optional key prefix inside the bucket                                    | `""`                     |
| `backupJob.config.encryptionKeyValueFrom.secretKeyRef`                     | Secret key containing the symmetric encryption key                       | `backup-config` / `encryptionKey` |
| `backupJob.image.repository`                                               | Backup container image repository                                        | `popen2/postgres-backup-s3` |
| `backupJob.image.tag`                                                      | Backup container image tag                                               | `v17.5`                  |
| `backupJob.serviceAccount.name`                                            | ServiceAccount for the backup job (IRSA target)                          | `platz-backup`           |
| `backupJob.serviceAccount.annotations`                                     | Annotations on the backup ServiceAccount                                 | `{}`                     |

### Scheduling and pod-level settings

| Name                  | Description                                              | Default |
| --------------------- | -------------------------------------------------------- | ------- |
| `nameOverride`        | Override the `name` portion of generated resource names  | `""`    |
| `fullnameOverride`    | Override the full resource name prefix                   | `""`    |
| `podAnnotations`      | Extra annotations applied to all Platz pods              | `{}`    |
| `podSecurityContext`  | Pod-level securityContext                                | `{}`    |
| `securityContext`     | Container-level securityContext                          | `{}`    |
| `nodeSelector`        | Node selector applied to all Platz pods                  | `{}`    |
| `tolerations`         | Tolerations applied to all Platz pods                    | `[]`    |
| `affinity`            | Affinity / anti-affinity applied to all Platz pods       | `{}`    |

You can pass any of these on the command line:

```bash
helm install platz platzio/platzio \
  -n platzio \
  --set auth.adminEmails='{me@example.com}' \
  --set ingress.enabled=true \
  --set ingress.rules[0].host=platz.example.com
```

For anything non-trivial, prefer a `values.yaml` file.

## Configuration and installation details

### Database

Platz treats Postgres as fully external. The chart does **not** bundle a Postgres dependency; you create the database, the role, and the secret yourself. Schema migrations run automatically on API startup.

The five `PG*` keys in `database.secretName` are injected as environment variables into every Platz pod that opens the database. There is no `DATABASE_URL` alternative.

For tuning connection pool behaviour under load, use `database.pool.*`. Each pod opens its own pool, so multiply per-pod limits by the total replica count when sizing your Postgres `max_connections`.

### Multi-cluster deployments

Platz can deploy into clusters other than the one it runs in. To wire that up:

1. Run one `k8sAgent.instances[]` per target cluster (or one with `provider: eks` to auto-discover EKS clusters via IAM).
2. Use IRSA / Workload Identity / equivalent to grant the agent's ServiceAccount the permissions it needs to assume a role in each target cluster.
3. Register each cluster in the Platz UI at `/admin/clusters` and attach it to an env.

The k8s-agent never holds long-lived cluster credentials in the database — it issues short-lived per-deployment tokens. Tune the rotation with `deploymentCredentialsRefreshInterval` and `deploymentCredentialsTokenDuration`.

### Chart discovery

Each `chartDiscovery.instances[]` entry watches a single registry. Two providers ship today:

- **`ecr`** — consumes EKS image push events from an SQS queue. Configure the queue and the IAM permissions yourself (or use the [terraform-aws-platzio](https://github.com/platzio/terraform-aws-platzio) module). This provider is event-driven and **does not backfill** historical charts.
- **`oci`** — polls any registry that implements the OCI Distribution Spec (Docker Distribution, zot, Harbor, GHCR, …). Lighter operational footprint, simpler permissions; the trade-off is the polling interval.

A chart is recognised when its OCI artifact's config media type is `application/vnd.cncf.helm.config.v1+json` — i.e. it was pushed with `helm push`.

### Ingress and `ownUrlOverride`

If `ingress.enabled=true`, Platz uses the first ingress host to construct the OIDC callback URL and the URLs surfaced by the Status feature. If you expose Platz some other way (NodePort, LoadBalancer, port-forward) set `ownUrlOverride` to the externally reachable URL instead.

The OIDC redirect URI is always `<base-url>/auth/google/callback`, regardless of which provider you've configured.

### Image pull secrets

If you mirror the Platz images into a private registry, set `imagePullSecrets` and override the three `images.*.repository` keys:

```yaml
imagePullSecrets:
  - name: my-registry-secret

images:
  backend:
    repository: registry.example.com/platzio/backend
  frontend:
    repository: registry.example.com/platzio/frontend
  helm:
    repository: registry.example.com/platzio/base
```

## Upgrading the Chart

Platz is currently in the `0.x` line. Minor version bumps may contain breaking changes; check [release notes](https://github.com/platzio/helm-charts/releases) before each upgrade.

```bash
helm repo update
helm upgrade platz platzio/platzio -n platzio -f platz-values.yaml
```

Schema migrations run automatically on API startup. Keep an eye on the API pod logs the first time you start a new chart version; if a migration fails, the pod exits and the old version keeps running on the other replicas (if you've scaled out).

## Documentation

- **[platz.io/docs](https://platz.io/docs)** — full user and admin guide.
- **[platz.io/docs/guide/install/helm](https://platz.io/docs/guide/install/helm)** — the canonical Helm installation walk-through.
- **[platz.io/docs/guide/install/terraform](https://platz.io/docs/guide/install/terraform)** — Terraform module for the EKS / ECR / SQS / S3 / IRSA layer that pairs with this chart.
- **[platz.io/docs/guide/chart-ext/overview](https://platz.io/docs/guide/chart-ext/overview)** — how to add a Chart Extension so your charts get a richer Platz UI.
- **[github.com/platzio/dev](https://github.com/platzio/dev)** — local development setup that brings Platz up on a `kind` cluster with Tilt.

## License

Apache 2.0. See [LICENSE](https://github.com/platzio/helm-charts/blob/main/charts/platzio/LICENSE).
