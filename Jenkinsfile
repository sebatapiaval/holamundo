pipeline {
  agent any

  parameters {
    booleanParam(name: 'RUN_BUILD',  defaultValue: true,  description: 'Construir imágenes Docker')
    booleanParam(name: 'RUN_PUSH',   defaultValue: false, description: 'Hacer login y push a Docker Hub')
    booleanParam(name: 'RUN_TF',     defaultValue: false, description: 'Aplicar Terraform')
    booleanParam(name: 'RUN_DEPLOY', defaultValue: false, description: 'Desplegar vía SSH')
  }

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
          def tag = sh(script: '''
            set -e
            TAG=""
            if [ -n "$GIT_COMMIT" ]; then
              TAG="$(printf '%s' "$GIT_COMMIT" | cut -c1-7)"
            fi
            if [ -z "$TAG" ]; then
              TAG="$(git rev-parse --short=7 HEAD 2>/dev/null || true)"
            fi
            if [ -z "$TAG" ]; then
              if [ -n "$BUILD_NUMBER" ]; then TAG="$BUILD_NUMBER"; else TAG="latest-$(date -u +%Y%m%d%H%M%S)"; fi
            fi
            printf "%s" "$TAG"
          ''', returnStdout: true).trim()

          env.IMAGE_TAG = tag
          echo "GIT_COMMIT: ${env.GIT_COMMIT ?: '(no definido)'}"
          echo "IMAGE_TAG: ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Preflight (versiones)') {
      steps {
        sh '''
          set -e
          echo "== Verificando herramientas en el agente =="
          git --version || true
          docker version || true
          terraform version || true
          ssh -V || true
        '''
      }
    }

    stage('Prepare SSH key (if missing)') {
      when { expression { params.RUN_DEPLOY || params.RUN_TF || true } } // usualmente igual conviene tenerla
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
      when { expression { params.RUN_BUILD } }
      steps {
        sh '''
          set -e
          [ -n "$IMAGE_TAG" ] || { echo "ERROR: IMAGE_TAG vacío"; exit 1; }
          docker build -t "$REGISTRY/$REPO/backend:$IMAGE_TAG" backend
          docker build -t "$REGISTRY/$REPO/frontend:$IMAGE_TAG" frontend
        '''
      }
    }

    stage('Docker Login + Push') {
      when { expression { params.RUN_PUSH } }
      environment { DOCKERHUB = credentials('dockerhub-cred') }
      steps {
        sh '''
          set -e
          [ -n "$IMAGE_TAG" ] || { echo "ERROR: IMAGE_TAG vacío"; exit 1; }
          echo "$DOCKERHUB_PSW" | docker login -u "$DOCKERHUB_USR" --password-stdin "$REGISTRY"
          docker push "$REGISTRY/$REPO/backend:$IMAGE_TAG"
          docker push "$REGISTRY/$REPO/frontend:$IMAGE_TAG"
          docker logout "$REGISTRY" || true
        '''
      }
    }

    stage('Terraform Apply (Infra)') {
      when { expression { params.RUN_TF } }
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
                -var="ssh_public_key=$(tr -d '\\n' < "$SSH_PUB")"
            '''
          }
        }
      }
    }

    stage('Get VM IP') {
      when { expression { params.RUN_DEPLOY || params.RUN_TF } }
      steps {
        script {
          env.INSTANCE_IP = sh(script: "cd $TF_DIR && terraform output -raw instance_ip", returnStdout: true).trim()
          if (!env.INSTANCE_IP) { error("No se obtuvo la IP de la VM desde Terraform.") }
          echo "VM IP: ${env.INSTANCE_IP}"
        }
      }
    }

    stage('Deploy via SSH (docker compose)') {
      when { expression { params.RUN_DEPLOY } }
      steps {
        sh '''
          set -e
          [ -n "$IMAGE_TAG" ]   || { echo "ERROR: IMAGE_TAG vacío"; exit 1; }
          [ -n "$INSTANCE_IP" ] || { echo "ERROR: INSTANCE_IP vacío"; exit 1; }

          mkdir -p deploy
          cat > deploy/.env <<EOF
REGISTRY=$REGISTRY
REPO=$REPO
IMAGE_TAG=$IMAGE_TAG
EOF

          scp -i "$SSH_KEY" -o StrictHostKeyChecking=no deploy/docker-compose.yml deploy/.env "$SSH_USER@$INSTANCE_IP:~/"
          ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$INSTANCE_IP" "docker compose pull && docker compose up -d && docker compose ps"
        '''
      }
    }
  }

  post {
    success { echo "✅ OK: http://${env.INSTANCE_IP ?: 'N/A'} (tag: ${env.IMAGE_TAG})" }
    failure { echo '❌ Falló el pipeline' }
    always  { echo "Log: IMAGE_TAG=${env.IMAGE_TAG}; INSTANCE_IP=${env.INSTANCE_IP}; GIT_COMMIT=${env.GIT_COMMIT}" }
  }
}
