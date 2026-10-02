# The same digest-pinned base every WebService proof ran (ADR-0022). It runs
# as an unprivileged user and listens on 8080. The page names this
# repository, so the image this pipeline builds is visibly not the base.
FROM public.ecr.aws/nginx/nginx-unprivileged@sha256:59678856b05324b7f6371f26eb1520be7fcd8bdc8ab380fc4913db8503e5a842
COPY site/ /usr/share/nginx/html/
