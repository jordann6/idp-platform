# ${{ values.repoName }}

A web service for ${{ values.team }}, created by the idp-platform service template.

- Pull requests run the platform guardrails: secret scan over full history, stack detection, and an image build with a Trivy scan.
- A merge to main publishes a linux/amd64 and linux/arm64 image to ECR Public and prints its digest in the job summary.
- To run that image, use the deploy template in the portal with the digest. It opens a pull request on idp-platform; merging it updates the service on ${{ values.cloud }}.

The page the service serves lives in site/. Change it, open a pull request, merge, then deploy the new digest.
