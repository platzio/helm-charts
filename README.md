# Platz Helm Chart

[Helm](https://helm.sh) must be installed to use the charts.  Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

    helm repo add platzio https://platzio.github.io/helm-charts

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages.  You can then run `helm search repo
platzio` to see the charts.

## To install the platzio chart

1. Create a namespace, for example:

   ```bash
   kubectl create ns platzio
   ```

1. Create a secret containing credentials for connecting to a PostgreSQL database:

   ```bash
   kubectl create secret generic -n platzio postgres-creds \
       --from-literal=PGHOST=pghost \
       --from-literal=PGPORT=5432 \
       --from-literal=PGUSER=postgres \
       --from-literal=PGPASSWORD=secret \
       --from-literal=PGDATABASE=platz
   ```

1. Install the chart:

   ```bash
   helm install platzio -n platzio platzio/platzio
   ```

## To uninstall the chart

```bash
helm delete platzio
```
