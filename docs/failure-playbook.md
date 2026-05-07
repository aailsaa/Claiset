# Failure playbook (common issues + quick fixes)

## 1) Terraform state lock error

Symptoms: `Error acquiring the state lock` in CI/local Terraform.

Actions:
```bash
# confirm no other apply is running first
terraform force-unlock <LOCK_ID>
```

Also check for parallel GitHub runs on the same env and cancel duplicates.

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

## 6) ExternalDNS Helm release times out

Symptoms: `helm_release.external_dns ... context deadline exceeded`.

Actions:
```bash
kubectl get pods -n platform -l app.kubernetes.io/name=external-dns -o wide
kubectl describe pod -n platform -l app.kubernetes.io/name=external-dns
kubectl get events -n platform --sort-by='.lastTimestamp'
```

Check scheduling capacity, image pull, and controller dependencies; then rerun apply.

## 7) Website DNS mismatch

Symptoms: Ingress has ALB address but public hostname does not resolve correctly.

Actions:
- verify registrar nameservers point to the Route53 hosted zone in use
- verify `route53_hosted_zone_id` secret/var targets the intended zone
- compare `kubectl get ingress` ADDRESS with public DNS answer (`dig`)
