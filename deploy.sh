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
trap 'echo "❌ An unexpected error occurred. Check $LOG_FILE for details." >&2' ERR

# ---------- Collect Parameters ----------
echo "🛠️  Collecting Deployment Parameters..."
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
  echo "❌ Error: All fields are required!"
  exit 1
fi

# ---------- Clone Repository ----------
echo "📦 Cloning repository..."
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
  echo "✅ Docker configuration found."
else
  echo "❌ No Dockerfile or docker-compose.yml found!"
  exit 1
fi
cd ..

# ---------- Test SSH Connection ----------
echo "🔗 Testing SSH connectivity..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo '✅ SSH connection successful.'"

# ---------- Prepare Remote Environment ----------
echo "⚙️  Preparing remote environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << 'EOF'
  set -e
  echo "🔧 Updating system..."
  sudo apt update -y && sudo apt upgrade -y

  echo "🔧 Installing Docker, Docker Compose, and Nginx..."
  sudo apt install -y docker.io docker-compose nginx

  echo "🔧 Adding user to Docker group..."
  sudo usermod -aG docker $USER

  echo "🔧 Enabling and starting services..."
  sudo systemctl enable docker nginx
  sudo systemctl start docker nginx

  echo "🔍 Installed Versions:"
  docker --version
  docker-compose --version
  nginx -v
EOF

# ---------- Deploy Dockerized Application ----------
echo "🚀 Deploying application to remote server..."
scp -i "$SSH_KEY" -r "./$REPO_DIR" "$SSH_USER@$SERVER_IP:/home/$SSH_USER/"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  cd /home/$SSH_USER/$REPO_DIR

  echo "🧹 Stopping old containers (if any)..."
  docker-compose down || true
  docker stop myapp || true
  docker rm myapp || true

  if [ -f "docker-compose.yml" ]; then
    echo "📦 Using docker-compose to deploy..."
    docker-compose up -d --build
  else
    echo "📦 Using Dockerfile to deploy..."
    docker build -t myapp .
    docker run -d -p $APP_PORT:$APP_PORT --name myapp myapp
  fi
EOF

# ---------- Configure Nginx Reverse Proxy ----------
echo "🌐 Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
sudo bash -c 'cat > /etc/nginx/sites-available/myapp.conf <<EOL
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL'

sudo ln -sf /etc/nginx/sites-available/myapp.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
EOF

# ---------- Validate Deployment ----------
echo "🧪 Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << EOF
  echo "🔍 Checking Docker containers..."
  docker ps

  echo "🔍 Checking Nginx status..."
  sudo systemctl status nginx --no-pager

  echo "🔍 Testing app endpoint..."
  curl -I http://localhost
EOF

# ---------- Completion Message ----------
echo "✅ Deployment completed successfully!"
echo "🌍 You can access your application at: http://$SERVER_IP"
echo "📜 Logs saved to: $LOG_FILE"
