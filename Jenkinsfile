pipeline {
  agent any

  environment {
    REGISTRY = "docker.io"
    REPO     = "sebatapiaval/holamundo"
    IMAGE_TAG = ''
    TF_DIR = 'infra/terraform'
    SSH_USER = 'ubuntu'
    SSH_DIR  = "${WORKSPACE}/.ssh"
    SSH_KEY  = "${WORKSPACE}/.ssh/id_rsa"
    SSH_PUB  = "${WORKSPACE}/.ssh/id_rsa.pub"
  }

  options { timestamps(); ansiColor('xterm') }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Set Tag') {
      steps { script { IMAGE_TAG = env.GIT_COMMIT?.take(7) ?: env.BUILD_NUMBER } }
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
        docker build -t $REGISTRY/$REPO/backend:$IMAGE_TAG backend
        docker build -t $REGISTRY/$REPO/frontend:$IMAGE_TAG frontend
        '''
      }
    }

    stage('Docker Login + Push') {
      environment { DOCKERHUB = credentials('dockerhub-cred') }
      steps {
        sh '''
        echo "$DOCKERHUB_PSW" | docker login -u "$DOCKERHUB_USR" --password-stdin $REGISTRY
        docker push $REGISTRY/$REPO/backend:$IMAGE_TAG
        docker push $REGISTRY/$REPO/frontend:$IMAGE_TAG
        docker logout $REGISTRY || true
        '''
      }
    }

    stage('Terraform Apply (Infra)') {
      environment { TF_IN_AUTOMATION = 'true' }
      steps {
        withCredentials([file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_CLOUD_KEY')]) {
          dir(TF_DIR) {
            sh '''
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
          echo "VM IP: ${env.INSTANCE_IP}"
        }
      }
    }

    stage('Deploy via SSH (docker compose)') {
      steps {
        sh '''
        # .env para compose con las imágenes recién publicadas
        cat > deploy/.env <<EOF
REGISTRY=$REGISTRY
REPO=$REPO
IMAGE_TAG=$IMAGE_TAG
EOF

        # Copiar compose y .env
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no deploy/docker-compose.yml deploy/.env $SSH_USER@$INSTANCE_IP:~/

        # Levantar en la VM
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_USER@$INSTANCE_IP \
          "docker compose pull && docker compose up -d && docker compose ps"
        '''
      }
    }
  }

  post {
    success { echo "✅ Deploy OK: http://$INSTANCE_IP" }
    failure { echo '❌ Falló el pipeline' }
  }
}
