# Auto-generate SSH key pair
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair from generated key
resource "aws_key_pair" "ec2_keypair" {
  key_name   = "frontend"  # This matches your error
  public_key = tls_private_key.ec2_key.public_key_openssh

  lifecycle {
    create_before_destroy = true
  }
}

# Save private key to local file
resource "local_file" "private_key" {
  content  = tls_private_key.ec2_key.private_key_pem
  filename = "./frontend.pem"
  file_permission = "0400"
}

resource "aws_security_group" "apps_sg" {
  name_prefix = "apps-sg-"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to your IP in production
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "apps-sg"
  }
}

resource "aws_instance" "app_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.apps_sg.id]
  key_name               = aws_key_pair.ec2_keypair.key_name  # Uses auto-created key!

  user_data = <<-EOF
#!/bin/bash
apt update -y
apt install -y python3 python3-pip nodejs npm git

# Flask backend setup
mkdir -p /app/backend && cd /app/backend
pip3 install flask flask-cors
cat > app.py << 'APP'
from flask import Flask, jsonify
from flask_cors import CORS
app = Flask(__name__)
CORS(app)
@app.route('/')
def hello(): return "Flask Backend OK on port 5000!"
@app.route('/api/data')
def data(): return jsonify({"status": "Backend running", "port": 5000})
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
APP
nohup python3 app.py > /app/flask.log 2>&1 &

# Express frontend setup
mkdir -p /app/frontend && cd /app/frontend
npm init -y
npm install express cors
cat > server.js << 'APP'
const express = require('express');
const cors = require('cors');
const path = require('path');
const app = express();
app.use(cors());
app.use(express.static('public'));
app.get('/', (req, res) => res.send('Express Frontend OK on port 3000!'));
app.get('/api', async (req, res) => {
  try {
    const backend = await fetch('http://localhost:5000/api/data');
    const data = await backend.json();
    res.json({status: 'Frontend proxying backend', backend: data});
  } catch(e) {
    res.json({status: 'Frontend OK', backend: 'unavailable'});
  }
});
app.listen(3000, () => console.log('Express on 3000'));
APP
mkdir -p public
cat > public/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head><title>Flask + Express</title></head>
<body>
  <h1>Express Frontend (port 3000)</h1>
  <button onclick="fetchData()">Call Backend API</button>
  <pre id="result"></pre>
  <script>
    async function fetchData() {
      try {
        const res = await fetch('/api');
        const data = await res.json();
        document.getElementById('result').textContent = JSON.stringify(data, null, 2);
      } catch(e) { document.getElementById('result').textContent = 'Error: ' + e; }
    }
  </script>
</body>
</html>
HTML
sed -i 's/"scripts": {/"scripts": {"start": "node server.js",/' package.json
nohup npm start > /app/express.log 2>&1 &

echo "Apps deployed! Check logs:"
echo "Flask: cat /app/flask.log"
echo "Express: cat /app/express.log"
EOF

  tags = {
    Name = "Flask-Express-Server"
  }
}

output "instance_public_ip" {
  value = aws_instance.app_server.public_ip
}

output "ssh_command" {
  value = "ssh -i frontend.pem ec2-user@${aws_instance.app_server.public_ip}"
}

