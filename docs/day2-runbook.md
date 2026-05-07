# Day 2 runbook 

## Scenario A: Node OS/security patching with no downtime

Goal: update worker nodes/AMI release while keeping app endpoints available.

1. **Pre-check health**

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get ingress -A
```

2. **Increase temporary headroom** (avoid scheduling pressure during rollout)

```bash
AWS_REGION=us-east-1 ./infra/scripts/eks-burst-scale.sh claiset-qa claiset-qa-default 1 4 6
```

3. **Apply EKS/nodegroup update** (Terraform)

```bash
cd infra/envs/qa
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=envs/qa/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
  -backend-config="encrypt=true"
terraform apply
```

4. **Observe rollout**

```bash
kubectl get nodes -w
kubectl get pods -A -w
```

Narration points:
- new nodes join before old nodes leave
- workloads keep replicas Ready
- Ingress endpoint remains reachable during rotation

5. **Scale back down for cost**

```bash
AWS_REGION=us-east-1 ./infra/scripts/eks-burst-scale.sh claiset-qa claiset-qa-default 1 2 6
```

## Scenario B: DB schema change rollout

Goal: safely deliver a schema update with application code.

1. **Create additive migration first** (`cmd/migrate/schema.sql`), e.g. add nullable column / new table.
2. **Ship app code that can read/write both old and new schema shape during transition.**
3. **Deploy normally**: the `migrate` Job runs before app Deployments.
4. **Verify migration success and app health**

```bash
kubectl get jobs -n qa
kubectl logs -n qa job/migrate
kubectl get pods -n qa
```

5. **Rollback story (narration)**
- if app deploy fails but migration succeeded, roll app image back first
- prefer backward-compatible migrations; avoid destructive drops in same release
- do cleanup (drop old columns) in a later release window
