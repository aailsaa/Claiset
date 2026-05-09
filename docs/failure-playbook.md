# Failure playbook (common issues + quick fixes)

## 1) Terraform state lock error

Symptoms: `Error acquiring the state lock` / `ConditionalCheckFailedException` from DynamoDB when Terraform starts.

**Common cause:** a GitHub Actions run was **cancelled** or the runner died while holding the lock. The lock row stays in the DynamoDB table until you clear it or it is force-unlocked.

**Before you unlock:** confirm **no** other `terraform apply` / promotion job is actively running for that environment (GitHub **Actions** tab, same `tf-<env>-…` concurrency group). Releasing the lock while a real apply is in progress can corrupt state.

**Fix:** use the **ID** from the error (UUID), after `terraform init` with the same backend as CI:

```bash
cd infra/envs/prod   # or dev / qa / uat
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=envs/prod/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
  -backend-config="encrypt=true"
terraform force-unlock -force <LOCK_ID>
```

Avoid `-lock=false` on routine applies; it bypasses protection for everyone.

Also cancel **duplicate** workflow runs targeting the same env so they do not fight over state.

## 2) `Too many pods` / controller or app pods stuck `Pending`

Symptoms: scheduler events show `0/x nodes are available: Too many pods`.

Actions:
```bash
kubectl describe pod -n platform <pod-name>
AWS_REGION=us-east-1 ./infra/scripts/eks-burst-scale.sh claiset-qa claiset-qa-default 1 4 6
```

Then rerun apply once pods can schedule.

## 3) ALB/Ingress has no ADDRESS

Symptoms: `kubectl get ingress -n <env>` shows empty ADDRESS; website unreachable.

Actions:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=120
```

If logs show `AccessDenied` on ELB APIs, ensure node IAM role has the ALB controller policy (managed in Terraform under `infra/modules/eks`).

## 4) ALB webhook TLS x509 failure

Symptoms: `failed calling webhook ... x509: certificate signed by unknown authority`.

Actions:
- ensured in Terraform: `enableServiceMutatorWebhook=false`
- ensured in Terraform: `webhookConfig.disableIngressValidation=true`
- rerun apply to update chart values and recreate affected resources

## 5) ACM certificate `ResourceInUseException` on delete

Symptoms: cannot delete cert because still attached to ALB/listener.

Actions:
- ensured in Terraform: `create_before_destroy = true` on `aws_acm_certificate.frontend`
- rerun apply so replacement cert is created/attached before old cert removal

## 6) Helm `cannot re-use a name that is still in use`

Symptoms: `helm_release.aws_load_balancer_controller` (or other platform/monitoring charts) fails to create after a **cancelled** or **partial** apply.

Actions: CI runs [`helm-platform-reconcile.sh`](../infra/scripts/helm-platform-reconcile.sh) (uninstalls **stuck** releases; **`terraform import`s** healthy **deployed** releases missing from state) then [`helm-monitoring-reconcile.sh`](../infra/scripts/helm-monitoring-reconcile.sh). Locally from `infra/envs/<env>` **after `terraform init`**:

```bash
export EXPECTED_CLUSTER_NAME=claiset-prod   # or dev / qa / uat
export AWS_REGION=us-east-1
bash ../../scripts/helm-platform-reconcile.sh
bash ../../scripts/helm-monitoring-reconcile.sh
```

Manual import if you prefer not to rely on the script:

```bash
terraform import 'module.platform.helm_release.aws_load_balancer_controller' 'kube-system/aws-load-balancer-controller'
```

## 7) ExternalDNS Helm release times out

Symptoms: `helm_release.external_dns ... context deadline exceeded`.

Actions:
```bash
kubectl get pods -n platform -l app.kubernetes.io/name=external-dns -o wide
kubectl describe pod -n platform -l app.kubernetes.io/name=external-dns
kubectl get events -n platform --sort-by='.lastTimestamp'
```

Check scheduling capacity, image pull, and controller dependencies; then rerun apply.

## 8) Website DNS mismatch

Symptoms: Ingress has ALB address but public hostname does not resolve correctly.

Actions:
- verify registrar nameservers point to the Route53 hosted zone in use
- verify `route53_hosted_zone_id` secret/var targets the intended zone
- compare `kubectl get ingress` ADDRESS with public DNS answer (`dig`)

## 9) `terraform import` — *Configuration for import target does not exist*

Symptoms: importing `module.platform.kubernetes_namespace.monitoring[0]` (or other observability addresses) fails with that message.

**Cause:** `monitoring` and related resources use `count` and only exist when **`local.observability_enabled`** is true in `infra/modules/platform/observability.tf`. That requires **`enable_observability_stack`**, **`domain_root`**, **`wait_for_acm_validation`**, and non-empty **Grafana OAuth** id/secret. GitHub Actions sets these via `TF_VAR_*`; **`infra/envs/prod` defaults** use `enable_observability_stack = false` and empty Grafana vars, so locally there is **no** `monitoring[0]` in the configuration graph until you pass the same inputs as CI.

**Fix:** from `infra/envs/prod`, export the same variables you use in Actions (or use a private `terraform.tfvars` you do not commit), then import:

```bash
export TF_VAR_enable_observability_stack=true
export TF_VAR_grafana_google_client_id='your-web-client-id.apps.googleusercontent.com'
export TF_VAR_grafana_google_client_secret='your-secret'
# If you use a hosted zone secret in CI:
export TF_VAR_route53_hosted_zone_id='Z...'

terraform import 'module.platform.kubernetes_namespace.monitoring[0]' monitoring
terraform import 'module.platform.kubernetes_secret.grafana_google_oauth[0]' monitoring/grafana-google-oauth
```

If Helm reports observability chart names already in use, from the same directory run `EXPECTED_CLUSTER_NAME=… bash ../../scripts/helm-monitoring-reconcile.sh` (imports **deployed** `kube-prometheus-stack` / `loki` / `promtail` when missing from state).

Then run `terraform plan` and continue with apply or let the workflow run (CI runs **k8s import guard** + **helm-monitoring-reconcile** with the correct env).

## 10) Migrate `Job` — refresh / import errors

Symptoms: `kubernetes_job.migrate` fails on **refresh** during apply (`Refreshing state... [id=prod/migrate]`) or import guard logs **Cannot import non-existent remote object** for `prod/migrate`.

**Cause:** The one-shot migrate Job finished and was **removed** from the cluster (or never created) while **Terraform state** still tracks it. Apply tries to refresh a missing object and errors.

**Fix:** The **k8s import guard** removes that address from state when the job is missing so the next apply **recreates** it. If you need to do it manually: `terraform state rm 'module.eks_app.kubernetes_job.migrate[0]'` from `infra/envs/<env>` (then re-apply). The guard’s **“Skipping Job … import failed”** line when the job does not exist yet is normal and not a failed step by itself.

## 11) EKS managed node group: `NodeCreationFailure` / new nodes not joining

Symptoms: `waiting for EKS Node Group ... unexpected state 'Failed' ... NodeCreationFailure: ... new nodes are not joining`.

**Common causes:** launch template / instance-type rollouts racing `$Latest`, **insufficient EC2 capacity** for the chosen type/AZ, subnets/NAT so nodes cannot reach the **public** EKS API endpoint, or a **stuck** partial update after a **`-target`** apply.

**In AWS Console:** EKS → cluster → **Compute** → node group → **Health issues** and **Events**; EC2 → instances launched by the node group ASG → **Status checks** and **Get system log** (bootstrap/kubelet errors).

**After a failed update:** when no other apply is running, retry from the same `infra/envs/<env>` after `terraform init` (same backend as CI), then a **full** `terraform plan` (avoid `-target` unless you are recovering a documented partial apply). The EKS module pins the **launch template version** and sets **`update_config`** so rolls are less likely to wedge.

**If capacity is the issue:** temporarily switch `node_instance_types` (e.g. try `t3a.medium` instead of `t3.medium` in `infra/envs/prod/variables.tf`) and re-apply, or change **capacity**/AZ by adjusting the node group.

**If the node group stays `DEGRADED`/`FAILED`:** use AWS support guidance / Console **Rollback** or open a case; avoid cancelling mid-apply. Do not `force-unlock` while a real node group update is still running in AWS.
