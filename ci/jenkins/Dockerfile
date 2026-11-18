# =====================================================================
# Home IoT 빌드용 Jenkins 이미지 (t1-base 에서 docker compose 로 실행)
#  - Jenkins LTS + 플러그인(plugins.txt) + JCasC 설정(casc.yaml)
#  - 파이프라인에 필요한 도구: docker CLI(+buildx), git, Node.js 22, kubectl(kustomize 렌더링 확인용)
#  - 이미지 빌드는 호스트(t1-base)의 docker 데몬을 소켓으로 사용
# =====================================================================
FROM jenkins/jenkins:lts-jdk21

USER root
ARG KUBECTL_MINOR=v1.37
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg git jq \
 # Docker CLI
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
 # kubectl
 && curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBECTL_MINOR}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/${KUBECTL_MINOR}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list \
 # Node.js 22
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin kubectl nodejs \
 && rm -rf /var/lib/apt/lists/*

USER jenkins
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Duser.timezone=Asia/Seoul" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/ref/casc.yaml
