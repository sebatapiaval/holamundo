pipeline {
  agent any

  environment {
    REGISTRY   = 'docker.io'
    REPO       = 'sebatapiaval/holamundo'
    IMAGE_TAG  = ''
    TF_DIR     = 'infra/terraform'
    SSH_USER   = 'ubuntu'
    SSH_DIR    = "${WORKSPACE}/.ssh"
    SSH_KEY    = "${WORKSPACE}/.ssh/id_rsa"
    SSH_PUB    = "${WORKSPACE}/.ssh/id_rsa.pub"
  }

  options { timestamps(); ansiColor('xterm') }

  stages {
    stage('Set Tag') {
      steps {
        script {
          // 1) Intentar con la var inyectada por Jenkins
          def sha = (env.GIT_COMMIT && env.GIT_COMMIT.size() >= 7) ? env.GIT_COMMIT.take(7) : ''

          // 2) Si no hay, intentar desde git
          if (!sha?.trim()) {
            sh 'git fetch --all --tags || true'
            sha = sh(script: 'git rev-parse --short=7 HEAD || true', returnStdout: true).trim()
          }

          // 3) Fallbacks finales
          def fallback = env.BUILD_NUMBER ?: "latest-${new Date().format('yyyyMMddHHmmss', TimeZone.getTimeZone('UTC'))}"
          env.IMAGE_TAG = (sha?.trim()) ? sha.trim() : fallback

          echo "GIT_COMMIT visto por Jenkins: ${env.GIT_COMMIT ?: '(no definido)'}"
          echo "Image tag calculado: ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Prepare SSH key (if missing)') {
      steps {
        sh '''
          set -e
          mkdir -p "$SSH_DIR"
          if [ ! -f "$SSH_KEY" ]; then
            ssh-keygen -t rsa -b 4096 -C "jenkins@vm" -N "" -f "$SSH_KEY"
          fi
          chmod 700 "$SSH_DIR"
          chmod 600 "$SSH_KEY"
          chmod 644 "$SSH_PUB"
          echo "SSH key ready: $SSH_KEY"
        '''
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          set -e
          if [ -z "$IMAGE_TAG" ]; then
            echo "ERROR: IMAGE_TAG está vacío"; exit 1
          fi
          docker build -t "$REGISTRY/$REPO/backend:$IMAGE_TAG" backend
          docker build -t "$REGISTRY/$REPO/frontend:$IMAGE_TAG" frontend
        '''
      }
    }

    stage('Docker Login + Push') {
      environment { DOCKERHUB = credentials('dockerhub-cred') } // DOCKERHUB_USR / DOCKERHUB_PSW
      steps {
        sh '''
          set -e
          if [ -z "$IMAGE_TAG" ]; then
            echo "ERROR: IMAGE_TAG está vacío"; exit 1
          fi
          echo "$DOCKERHUB_PSW" | docker login -u "$DOCKERHUB_USR" --password-stdin "$REGISTRY"
          docker push "$REGISTRY/$REPO/backend:$IMAGE_TAG"
          docker push "$REGISTRY/$REPO/frontend:$IMAGE_TAG"
          docker logout "$REGISTRY" || true
        '''
      }
    }

    stage('Terraform Apply (Infra)') {
      environment { TF_IN_AUTOMATION = 'true' }
      steps {
        withCredentials([file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_CLOUD_KEY')]) {
          dir(TF_DIR) {
            sh '''
              set -e
              terraform init -input=false
              terraform apply -input=false -auto-approve \
                -var="project_id=apiux-lab-devops" \
                -var="credentials_file=$GOOGLE_CLOUD_KEY" \
                -var="ssh_user=$SSH_USER" \
                -var="ssh_public_key=$(cat "$SSH_PUB")"
            '''
          }
        }
      }
    }

    stage('Get VM IP') {
      steps {
        script {
          env.INSTANCE_IP = sh(script: "cd $TF_DIR && terraform output -raw instance_ip", returnStdout: true).trim()
          if (!env.INSTANCE_IP) {
            error("No se obtuvo la IP de la VM desde Terraform.")
          }
          echo "VM IP: ${env.INSTANCE_IP}"
        }
      }
    }

    stage('Deploy via SSH (docker compose)') {
      steps {
        sh '''
          set -e
          if [ -z "$IMAGE_TAG" ]; then
            echo "ERROR: IMAGE_TAG está vacío"; exit 1
          fi
          if [ -z "$INSTANCE_IP" ]; then
            echo "ERROR: INSTANCE_IP está vacío"; exit 1
          fi

          # .env para compose con las imágenes recién publicadas
          mkdir -p deploy
          cat > deploy/.env <<EOF
REGISTRY=$REGISTRY
REPO=$REPO
IMAGE_TAG=$IMAGE_TAG
EOF

          # Copiar compose y .env
          scp -i "$SSH_KEY" -o StrictHostKeyChecking=no deploy/docker-compose.yml deploy/.env "$SSH_USER@$INSTANCE_IP:~/"

          # Levantar en la VM
          ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$INSTANCE_IP" \
            "docker compose pull && docker compose up -d && docker compose ps"
        '''
      }
    }
  }

  post {
    success {
      echo "✅ Deploy OK: http://${env.INSTANCE_IP} (tag: ${env.IMAGE_TAG})"
    }
    failure {
      echo '❌ Falló el pipeline'
    }
    always {
      // En Groovy, usa env.VAR (no $VAR)
      echo "Log: IMAGE_TAG=${env.IMAGE_TAG}; INSTANCE_IP=${env.INSTANCE_IP}; GIT_COMMIT=${env.GIT_COMMIT}"
    }
  }
}
