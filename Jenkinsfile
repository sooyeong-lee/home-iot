// =====================================================================
// Home IoT CI/CD (Jenkins 버전) : Jenkins → GHCR → (매니페스트 갱신) → Argo CD
//   이 프로젝트의 CI (가이드 7절). .github/workflows/ci-cd.yml 은 같은 일을 하는 참고용(수동 실행만, 가이드 10절)
//
//  PR / 기능 브랜치 : 테스트 · 이미지 빌드 · Trivy 검사 (push 없음)
//  main            : 위 + GHCR push (sha-xxxxxxx, latest)
//                    + deploy/k8s/overlays/gitops 의 이미지 태그 갱신 커밋 → Argo CD 자동 배포
//
// 필요한 Jenkins 자격증명 (ci/jenkins/casc.yaml 로 자동 등록)
//   github-token : Username = GitHub 아이디, Password = PAT (repo, write:packages)
// =====================================================================
def IMAGES = [
  [name: 'auth-service',      context: '.',     file: 'services/Dockerfile', service: 'auth-service'],
  [name: 'device-service',    context: '.',     file: 'services/Dockerfile', service: 'device-service'],
  [name: 'control-service',   context: '.',     file: 'services/Dockerfile', service: 'control-service'],
  [name: 'telemetry-service', context: '.',     file: 'services/Dockerfile', service: 'telemetry-service'],
  [name: 'simulator',         context: '.',     file: 'services/Dockerfile', service: 'simulator'],
  [name: 'web',               context: 'web',   file: 'web/Dockerfile',      service: ''],
  [name: 'web-nginx',         context: 'nginx', file: 'nginx/Dockerfile',    service: ''],
]

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 60, unit: 'MINUTES')
  }

  environment {
    GHCR_OWNER = 'sooyeong-lee'
    REPO_PATH  = 'sooyeong-lee/home-iot'
    GITOPS_KUSTOMIZATION = 'deploy/k8s/overlays/gitops/kustomization.yaml'
  }

  stages {
    stage('준비') {
      steps {
        script {
          env.TAG = "sha-${env.GIT_COMMIT.substring(0, 7)}"
          env.IS_MAIN = (env.BRANCH_NAME == 'main') ? 'true' : 'false'
          def subject = sh(script: 'git log -1 --pretty=%s', returnStdout: true).trim()
          // 파이프라인이 직접 만든 태그 커밋이면 다시 빌드하지 않음 (무한 반복 방지)
          env.SKIP = subject.startsWith('chore(deploy):') ? 'true' : 'false'
          echo "branch=${env.BRANCH_NAME} tag=${env.TAG} main=${env.IS_MAIN} skip=${env.SKIP}"
          if (env.SKIP == 'true') { currentBuild.description = '매니페스트 갱신 커밋 → 건너뜀' }
        }
      }
    }

    stage('테스트') {
      when { environment name: 'SKIP', value: 'false' }
      steps {
        sh '''
          node -v
          npm test
          for f in $(git ls-files 'packages/**/*.js' 'services/**/*.js' 'tools/**/*.js' 'scripts/*.js'); do node --check "$f"; done
          kubectl kustomize deploy/k8s/overlays/gitops > /dev/null
        '''
      }
    }

    stage('이미지 빌드 · Trivy') {
      when { environment name: 'SKIP', value: 'false' }
      steps {
        script {
          for (img in IMAGES) {
            def ref = "ghcr.io/${env.GHCR_OWNER}/home-iot/${img.name}"
            def arg = img.service ? "--build-arg SERVICE=${img.service}" : ''
            stage("build ${img.name}") {
              sh """
                docker build --pull ${arg} -f ${img.file} \
                  --label org.opencontainers.image.source=https://github.com/${env.REPO_PATH} \
                  --label org.opencontainers.image.revision=${env.GIT_COMMIT} \
                  -t ${ref}:${env.TAG} -t ${ref}:latest ${img.context}
                # CRITICAL(수정판 있는 것) 취약점이 있으면 실패
                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/trivy \
                  aquasec/trivy:latest image --severity CRITICAL --ignore-unfixed --exit-code 1 --no-progress ${ref}:${env.TAG}
              """
            }
          }
        }
      }
    }

    stage('GHCR push') {
      when { allOf { environment name: 'SKIP', value: 'false'; environment name: 'IS_MAIN', value: 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
          script {
            sh 'echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_USER" --password-stdin'
            try {
              for (img in IMAGES) {
                def ref = "ghcr.io/${env.GHCR_OWNER}/home-iot/${img.name}"
                sh "docker push ${ref}:${env.TAG} && docker push ${ref}:latest"
              }
            } finally {
              sh 'docker logout ghcr.io || true'
            }
          }
        }
      }
    }

    stage('배포 매니페스트 갱신 (GitOps)') {
      when { allOf { environment name: 'SKIP', value: 'false'; environment name: 'IS_MAIN', value: 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
          sh '''
            set -e
            git config user.name  "jenkins"
            git config user.email "jenkins@t1-base.local"
            # 토큰을 URL 에 넣지 않고 credential helper 로 전달
            export GIT_ASKPASS_HELPER='!f() { echo username=$GH_USER; echo password=$GH_TOKEN; }; f'
            git -c credential.helper="$GIT_ASKPASS_HELPER" fetch origin main
            git checkout -B main origin/main
            sed -i -E "s#newName: ghcr.io/[^/]+/home-iot/#newName: ghcr.io/${GHCR_OWNER}/home-iot/#; s#newTag: .*#newTag: ${TAG}#" "$GITOPS_KUSTOMIZATION"
            grep -E "newName|newTag" "$GITOPS_KUSTOMIZATION"
            git add "$GITOPS_KUSTOMIZATION"
            if git diff --cached --quiet; then echo "변경 없음"; exit 0; fi
            git commit -m "chore(deploy): 이미지 ${TAG} 배포"
            for i in 1 2 3; do
              git -c credential.helper="$GIT_ASKPASS_HELPER" pull --rebase origin main && \
              git -c credential.helper="$GIT_ASKPASS_HELPER" push origin HEAD:main && exit 0
              sleep 5
            done
            exit 1
          '''
        }
      }
    }
  }

  post {
    always {
      // 오래된 이미지 정리 (t1-base 디스크 보호). 실패해도 무시
      sh 'docker image prune -f --filter "until=72h" >/dev/null 2>&1 || true'
    }
  }
}
