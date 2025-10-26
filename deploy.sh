#!/bin/bash
# ===============================================
# Automated Dockerized App Deployment Script
# Author: Izuchukwu Osondu
# ===============================================

set -e  # Stop on error
set -o pipefail

#!/bin/bash
# ===============================================
# Automated Dockerized App Deployment Script
# Author: Izuchukwu Osondu
# ===============================================

set -e  # Stop on error
set -o pipefail

# ---------- Logging Setup ----------
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "An unexpected error occurred. Check $LOG_FILE for details." >&2' ERR

# ---------- Collect Parameters ----------
echo "Collecting Deployment Parameters..."
read -p "Enter Git Repository URL: " GIT_URL
read -p "Enter Personal Access Token (PAT): " PAT
read -p "Enter Branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter remote SSH username: " SSH_USER
read -p "Enter remote server IP address: " SERVER_IP
read -p "Enter path to SSH private key: " SSH_KEY
read -p "Enter application port (e.g., 8080): " APP_PORT

# ---------- Validate Input ----------
if [[ -z "$GIT_URL" || -z "$PAT" || -z "$SSH_USER" || -z "$SERVER_IP" || -z "$SSH_KEY" || -z "$APP_PORT" ]]; then
  echo "Error: All fields are required!"
  exit 1
fi

# ---------- Clone Repository ----------
echo "Cloning repository..."
REPO_DIR="app_repo"

if [ -d "$REPO_DIR" ]; then
  echo "🔄 Repository exists. Pulling latest changes..."
  cd "$REPO_DIR"
  git pull origin "$BRANCH"
  cd ..
else
  git clone -b "$BRANCH" "https://${PAT}@${GIT_URL#https://}" "$REPO_DIR"
fi

# ---------- Verify Docker Configuration ----------
echo "🔍 Checking Docker configuration..."
cd "$REPO_DIR"
if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
  echo "Docker configuration found."
else
  echo "No Dockerfile or docker-compose.yml found!"
  exit 1
fi
cd ..

# ---------- Test SSH Connection ----------
echo "Testing SSH connectivity..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo '✅ SSH connection successful.'"

# ---------- Prepare Remote Environment ----------
echo "Preparing remote environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << 'EOF'
  set -e
  sudo apt update -y && sudo apt upgrade -y
  sudo apt install -y docker.io docker-compose
  sudo usermod -aG docker $USER
  sudo systemctl enable docker
  sudo systemctl start docker
EOF

# ---------- Deploy Dockerized Application ----------
echo "Deploying application to remote server..."
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" --exclude='.git/' "./$REPO_DIR/" "$SSH_USER@$SERVER_IP:/home/$SSH_USER/$REPO_DIR/"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  cd /home/$SSH_USER/$REPO_DIR

  echo "🧹 Stopping old containers (if any)..."
  docker-compose down || true
  docker rm my_docker_app || true

  # Ensure Nginx config is set up correctly
  cat > nginx.conf <<EOL
server {
    listen 80;
    location / {
        proxy_pass http://my_app:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;

  echo "Deploying application with docker-compose..."
  docker-compose up -d --build
EOF

# ---------- Validate Deployment ----------
echo "Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  echo "🔍 Checking Docker containers..."
  docker ps

  echo "Testing app endpoint..."
  curl -I http://localhost
EOF

# ---------- Completion Message ----------
echo "Deployment completed successfully!"
echo "You can access your application at: http://$SERVER_IP"
echo "Logs saved to: $LOG_FILE"
    }
}
EOL

