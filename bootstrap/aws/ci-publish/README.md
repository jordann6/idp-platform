# bootstrap/aws/ci-publish

One IAM role, idp-ci-publish, that GitHub Actions assumes through OIDC to push scaffolded services' images to ECR Public (ADR-0024). Standing cost is zero.

- Trust: audience sts.amazonaws.com and GitHub's immutable subject `repo:idp-platform-apps@337025991/*:ref:refs/heads/main`, so only main in that organization, matched by its numeric ID, can publish.
- Permissions: GetAuthorizationToken and GetServiceBearerToken (not narrowed by service name, which ECR Public's login does not present; the boundary makes a token for any other service useless), and on `repository/idp-platform-apps/*` create (with Project=idp-platform and a team-* Team tag, no other keys), tag on the same terms, push, and describe. No delete, no repository policy changes, nothing outside the prefix.
- Boundary: idp-ci-publish-boundary allows only ECR Public and the bearer token in us-east-1, and denies deletes, untagging, and repository policy changes outright.

Dependency outside this repository: the IAM OIDC provider for token.actions.githubusercontent.com was created elsewhere and is shared with other roles in the account. This root reads it with a data source and never manages it. If it is deleted, publishing fails at AssumeRoleWithWebIdentity until it is recreated with audience sts.amazonaws.com.

After apply, `make ci-publish` in bootstrap/k3s sets the role ARN as the organization Actions variable IDP_CI_PUBLISH_ROLE_ARN (needs the admin:org gh scope for that one command). The ARN carries the account ID and is never committed.
