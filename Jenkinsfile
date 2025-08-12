pipeline {
  agent any

  environment {
    REGISTRY = 'docker.io'
    REPO     = 'sebatapiaval/holamundo'   // repo único con tags backend/frontend
    TF_DIR   = 'infra/terraform'

    SSH_USER = 'ubuntu'
    SSH_DIR  = "${WORKSPACE}/.ssh"
    SSH_KEY  = "${WORKSPACE}/.ssh/id_rsa"
    SSH_PUB  = "${WORKSPACE}/.ssh/id_rsa.pub"
  }

  options { timestamps(); ansiColor('xterm') }

  stages {

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
          docker build -t "$REGISTRY/$REPO:backend-latest"  backend
          docker build -t "$REGISTRY/$REPO:frontend-latest" frontend
        '''
      }
    }

    stage('Docker Login + Push') {
      environment { DOCKERHUB = credentials('dockerhub-cred') } // DOCKERHUB_USR / DOCKERHUB_PSW
      steps {
        sh '''
          set -e
          echo "$DOCKERHUB_PSW" | docker login -u "$DOCKERHUB_USR" --password-stdin "$REGISTRY"
          docker push "$REGISTRY/$REPO:backend-latest"
          docker push "$REGISTRY/$REPO:frontend-latest"
          docker logout "$REGISTRY" || true
        '''
      }
    }

    stage('Terraform Validate') {
      steps {
        dir(TF_DIR) {
          sh '''
            set -e
            terraform init -input=false -reconfigure
            terraform validate
          '''
        }
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
              PUB_KEY="$(tr -d '\\n' < "$SSH_PUB")"
              terraform apply -input=false -auto-approve \
                -var="project_id=apiux-lab-devops" \
                -var="credentials_file=$GOOGLE_CLOUD_KEY" \
                -var="ssh_user=$SSH_USER" \
                -var="ssh_public_key=$PUB_KEY"
            '''
          }
        }
      }
    }

    stage('Get VM IP') {
      steps {
        script {
          env.INSTANCE_IP = sh(script: "cd $TF_DIR && terraform output -raw instance_ip", returnStdout: true).trim()
          if (!env.INSTANCE_IP) { error("No se obtuvo la IP de la VM desde Terraform.") }
          echo "VM IP: ${env.INSTANCE_IP}"
        }
      }
    }

    stage('Deploy via SSH (docker compose)') {
      steps {
        sh '''
          set -e

          echo "Esperando 120 segundos para que la VM termine de iniciar..."
          sleep 120

          echo "Verificando conexión SSH a $INSTANCE_IP ..."
          for i in $(seq 1 10); do
            if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$INSTANCE_IP" "echo ready" >/dev/null 2>&1; then
              echo "SSH OK en intento $i"
              break
            fi
            echo "SSH aún no responde (intento $i). Reintentando en 5s..."
            sleep 5
          done

          # Esperar a que cloud-init termine (si existe)
          ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$INSTANCE_IP" \
            'if command -v cloud-init >/dev/null 2>&1; then sudo cloud-init status --wait || true; fi'

          # Instalar Docker en caliente si no está (idempotente)
          ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$INSTANCE_IP" '
            set -e
            if ! command -v docker >/dev/null 2>&1; then
              echo "Docker no está, instalando..."
              sudo apt-get update -y
              sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
              sudo install -m 0755 -d /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              sudo chmod a+r /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
              sudo apt-get update -y
              sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
              sudo usermod -aG docker '"$SSH_USER"' || true
              sudo systemctl enable docker --now
              echo "Docker instalado."
            else
              echo "Docker ya está instalado."
              # asegurar compose plugin
              if ! docker compose version >/dev/null 2>&1; then
                echo "Instalando plugin docker compose..."
                sudo apt-get update -y
                sudo apt-get install -y docker-compose-plugin
              fi
            fi
          '

          # Copiar docker-compose.yml y desplegar (pull always)
          scp -i "$SSH_KEY" -o StrictHostKeyChecking=no deploy/docker-compose.yml "$SSH_USER@$INSTANCE_IP:~/"

          ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$INSTANCE_IP" \
            "docker compose up -d --pull always && docker compose ps"
        '''
      }
    }
  }

  post {
    success { echo "✅ Deploy OK: http://${env.INSTANCE_IP}" }
    failure { echo '❌ Falló el pipeline' }
    always  { echo "Log: INSTANCE_IP=${env.INSTANCE_IP}" }
  }
}
