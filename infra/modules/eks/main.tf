locals {
  name = "${var.project}-${var.env}"
}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "eks_assume_role" {
  count = var.create_iam_roles ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count              = var.create_iam_roles ? 1 : 0
  name               = "${local.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_service_policy" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_security_group" "cluster" {
  name        = "${local.name}-eks-cluster"
  description = "EKS control plane security group"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

locals {
  resolved_cluster_role_arn = var.create_iam_roles ? aws_iam_role.cluster[0].arn : var.cluster_role_arn
}

resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = local.resolved_cluster_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_service_policy,
  ]

  tags = var.tags
}

data "aws_iam_policy_document" "node_assume_role" {
  count = var.create_iam_roles ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count              = var.create_iam_roles ? 1 : 0
  name               = "${local.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# AWS Load Balancer Controller is installed without IRSA and uses the node instance role (IMDS).
# Without ELBv2 permissions the controller cannot create ALBs; Ingress ADDRESS stays empty.
# Policy source: kubernetes-sigs/aws-load-balancer-controller docs/install/iam_policy.json (v2.10.0).
resource "aws_iam_policy" "node_aws_load_balancer_controller" {
  count       = var.create_iam_roles ? 1 : 0
  name        = "${local.name}-node-aws-lb-controller"
  description = "Permissions for AWS Load Balancer Controller when using node IAM role instead of IRSA."
  policy      = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "node_aws_load_balancer_controller" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = aws_iam_policy.node_aws_load_balancer_controller[0].arn
}

resource "aws_security_group" "node" {
  name        = "${local.name}-eks-nodes"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "node_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.node.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Nodes need outbound to reach EKS endpoint and AWS services"
}

resource "aws_security_group_rule" "cluster_from_nodes_443" {
  type                     = "ingress"
  security_group_id        = aws_security_group.cluster.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node.id
  description              = "Control plane from nodes"
}

resource "aws_security_group_rule" "nodes_intra_all" {
  type              = "ingress"
  security_group_id = aws_security_group.node.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  description       = "Node-to-node communication"
}

resource "aws_security_group_rule" "cluster_to_nodes_kubelet_10250" {
  type                     = "ingress"
  security_group_id        = aws_security_group.node.id
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  description              = "Control plane to kubelet"
}

resource "aws_security_group_rule" "cluster_to_nodes_pods_1025_65535" {
  type                     = "ingress"
  security_group_id        = aws_security_group.node.id
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  description              = "Control plane to pods"
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${local.name}-nodes-"

  vpc_security_group_ids = [aws_security_group.node.id]

  # Pods (like aws-load-balancer-controller/external-dns) often use the node IAM role
  # via EC2 Instance Metadata Service. The hop limit must allow pod network hops.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tags = var.tags
}

locals {
  resolved_node_role_arn = var.create_iam_roles ? aws_iam_role.node[0].arn : var.node_role_arn
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name}-default"
  node_role_arn   = local.resolved_node_role_arn
  subnet_ids      = var.subnet_ids
  # Omit `version` unless explicitly pinned (see variable `node_group_kubernetes_version`).
  # Pinning to `aws_eks_cluster.this.version` forces UpdateNodegroupVersion whenever the
  # control plane version changes, often in the same apply as launch template revisions.
  # AWS then frequently fails with InvalidParameterException about launch template instance types.
  version = var.node_group_kubernetes_version

  # Allow EKS/ASG to pick from multiple types for capacity. This significantly reduces
  # NodeCreationFailure during nodegroup updates when one type/AZ is temporarily out of capacity.
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  # Pin concrete LT version so the node group never applies an older template revision while AWS
  # rolls instances (reduces NodeCreationFailure from template/instance-type drift).
  launch_template {
    id      = aws_launch_template.nodes.id
    version = tostring(aws_launch_template.nodes.latest_version)
  }

  # Lets EKS replace more than one old node at a time when LT/instance type changes (within ASG limits).
  update_config {
    max_unavailable_percentage = 33
  }

  lifecycle {
    # CI intentionally bursts nodegroup desired_size during rollouts/smoke.
    # Ignoring desired_size drift prevents Terraform apply from scaling back down
    # mid-run and starving critical pods/jobs (e.g., prod migrate + observability).
    # If live desired < min_size (e.g. manual scale-down), pre-burst before apply or AWS returns
    # InvalidParameterException: minimum capacity can't be greater than desired size.
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  # Tags required for Cluster Autoscaler ASG auto-discovery.
  # These propagate to the underlying Auto Scaling Group created by the managed node group.
  tags = merge(var.tags, {
    "k8s.io/cluster-autoscaler/enabled"                      = "true"
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.this.name}" = "owned"
  })
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

# IRSA / OIDC provider (needed for controllers like cluster-autoscaler).
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

