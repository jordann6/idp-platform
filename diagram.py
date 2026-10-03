"""Architecture diagrams for the README, rendered to docs/*.png.

Run from the repository root: python3 diagram.py
Vendor icons come from the diagrams library; Crossplane, Kyverno, and
Backstage use the CNCF artwork, and Artifact Registry the Google Cloud icon
pack, both saved under docs/icons.
"""

import os

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, Fargate
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import ALB, CloudFront, VPC
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import S3
from diagrams.azure.compute import ContainerApps, ContainerRegistries
from diagrams.azure.database import DatabaseForPostgresqlServers
from diagrams.azure.identity import ManagedIdentities
from diagrams.azure.network import VirtualNetworks
from diagrams.custom import Custom
from diagrams.gcp.compute import Run
from diagrams.gcp.database import SQL
from diagrams.gcp.network import VPC as GcpVPC
from diagrams.gcp.security import Iam
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.client import Users
from diagrams.onprem.container import K3S
from diagrams.onprem.gitops import ArgoCD
from diagrams.onprem.vcs import Github

ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs", "icons")
GRAPH = {"fontsize": "20", "bgcolor": "white", "pad": "0.6", "nodesep": "0.5", "ranksep": "0.9"}


def crossplane(label):
    return Custom(label, f"{ICONS}/crossplane.png")


def kyverno(label):
    return Custom(label, f"{ICONS}/kyverno.png")


def backstage(label):
    return Custom(label, f"{ICONS}/backstage.png")


def artifact_registry(label):
    return Custom(label, f"{ICONS}/artifact-registry.png")


with Diagram(
    "idp-platform: one API, three clouds",
    filename="docs/architecture",
    outformat="png",
    graph_attr=GRAPH,
    show=False,
    direction="LR",
):
    dev = Users("Developer")

    with Cluster("GitHub  ·  jordann6/idp-platform"):
        repo = Github("claims/<team>/\ncatalog entities\nCompositions, XRDs\npolicies")

    with Cluster("Control plane  ·  K3s in a Lima VM (ADR-0010)"):
        portal = backstage("Backstage\nscaffolder templates")
        argo = ArgoCD("Argo CD\napp of apps")
        policy = kyverno("Kyverno\n10 ValidatingPolicies")
        xp = crossplane("Crossplane v2\nDatabase + WebService XRDs\none Composition per cloud")

    with Cluster("AWS  ·  us-east-1"):
        rds = RDSPostgresqlInstance("RDS PostgreSQL\nDatabase")
        with Cluster("per session  ·  bootstrap/aws/ingress"):
            aws_cache = ECR("ECR pull-through cache\nof ECR Public")
            alb = ALB("shared HTTPS ALB\n<name>.<team>.apps")
        fargate = Fargate("ECS Fargate (ARM64)\nWebService")

    with Cluster("GCP  ·  us-east1"):
        cloudsql = SQL("Cloud SQL PostgreSQL\nDatabase")
        gcp_cache = artifact_registry("Artifact Registry\nremote repo of ECR Public")
        cloudrun = Run("Cloud Run v2\nWebService")

    with Cluster("Azure  ·  eastus2"):
        flex = DatabaseForPostgresqlServers("Postgres Flexible Server\nDatabase")
        with Cluster("per session  ·  bootstrap/azure/apps"):
            az_cache = ContainerRegistries("ACR cache rule\nof ECR Public")
            aca = ContainerApps("Container Apps\nWebService")

    dev >> Edge(label="run a template") >> portal
    portal >> Edge(label="pull request") >> repo
    repo >> Edge(label="sync main") >> argo
    argo >> Edge(label="namespaced XRs") >> xp
    policy - Edge(style="dashed", label="admission") - xp

    xp >> Edge(label="provider-aws") >> rds
    xp >> fargate
    xp >> Edge(label="provider-gcp") >> cloudsql
    xp >> cloudrun
    xp >> Edge(label="provider-azure") >> flex
    xp >> aca

    alb >> Edge(label="host rule") >> fargate
    aws_cache >> Edge(style="dashed", label="image") >> fargate
    gcp_cache >> Edge(style="dashed", label="image") >> cloudrun
    az_cache >> Edge(style="dashed", label="image") >> aca


with Diagram(
    "Keyless identity: no long-lived cloud credential anywhere",
    filename="docs/identity",
    outformat="png",
    graph_attr=GRAPH,
    show=False,
    direction="LR",
):
    with Cluster("Control plane  ·  K3s"):
        providers = crossplane("Crossplane providers\nprojected service account tokens\nfixed names (ADR-0011)")
        portal = backstage("Backstage")

    with Cluster("K3s OIDC issuer  ·  bootstrap/aws/oidc-issuer"):
        bucket = S3("private S3 bucket\ndiscovery + JWKS")
        cdn = CloudFront("CloudFront + OAC\npublic issuer URL")
        bucket >> cdn

    with Cluster("AWS"):
        aws_role = IAMRole("idp-crossplane-provider-aws\nAssumeRoleWithWebIdentity\npermissions boundary")
    with Cluster("Azure"):
        uami = ManagedIdentities("user-assigned identity\nfederated credentials\nexact subject")
    with Cluster("GCP"):
        wif = Iam("Workload Identity pool\nimpersonates the provider\nservice account")

    providers >> Edge(label="token signed by K3s") >> cdn
    cdn >> Edge(label="trust") >> aws_role
    cdn >> Edge(label="trust") >> uami
    cdn >> Edge(label="trust") >> wif

    with Cluster("GitHub"):
        gitops_app = Github("idp-platform-gitops App\nidp-platform only\nclaim pull requests")
        scaffolder_app = Github("idp-platform-scaffolder App\norg idp-platform-apps\ncreates repositories")
        actions = GithubActions("scaffolded repo CI\nGitHub OIDC, main only")

    portal >> Edge(label="1 hour installation tokens") >> [gitops_app, scaffolder_app]

    with Cluster("AWS  ·  bootstrap/aws/ci-publish"):
        ci_role = IAMRole("idp-ci-publish\nimmutable org-ID subject\nno delete")
        ecr_public = ECR("ECR Public\nidp-platform-apps/*")

    actions >> Edge(label="OIDC token") >> ci_role >> Edge(label="push") >> ecr_public


with Diagram(
    "Phase 6: repository, pipeline, infrastructure, catalog entry",
    filename="docs/scaffolding",
    outformat="png",
    graph_attr=GRAPH,
    show=False,
    direction="LR",
):
    dev = Users("Developer")
    portal = backstage("Backstage\nservice template\ndeploy template")

    with Cluster("GitHub org  ·  idp-platform-apps"):
        app_repo = Github("<team>.<name>\nbranch protection\nCODEOWNERS, ci.yml")
        ci = GithubActions("guardrails ci.yml\n+ publish job\nlinux/amd64 + arm64")

    with Cluster("GitHub  ·  jordann6/idp-platform"):
        pr = Github("claim + Component\nreviewed pull request")

    ecr_public = ECR("ECR Public\npublic.ecr.aws/<alias>/\nidp-platform-apps/<team>.<name>")

    with Cluster("Control plane"):
        argo = ArgoCD("Argo CD")
        xp = crossplane("Crossplane\nWebService XR")

    with Cluster("Team's cloud (from the team Group)"):
        runtime = [Fargate("ECS Fargate"), Run("Cloud Run"), ContainerApps("Container Apps")]

    dev >> Edge(label="1. service") >> portal
    portal >> Edge(label="2. create repo\n(scaffolder App)") >> app_repo
    portal >> Edge(label="3. open PR on base image\n(gitops App)") >> pr
    app_repo >> Edge(label="push to main") >> ci
    ci >> Edge(label="4. publish by OIDC\ndigest in job summary") >> ecr_public
    pr >> Edge(label="merge") >> argo >> xp >> runtime
    dev >> Edge(style="dashed", label="5. deploy with the digest") >> portal
    ecr_public >> Edge(style="dashed", label="pulled through each cloud's cache") >> runtime[0]
    ecr_public >> Edge(style="dashed") >> runtime[1]
    ecr_public >> Edge(style="dashed") >> runtime[2]
