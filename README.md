# VPS Deploy Bot 🚀 — by **Gp TEAM**

Lightweight, modular **Discord bot** and **Docker automation** system that allows you to deploy, manage, and monitor multiple Linux-based VPS containers directly from Discord.

---

## ✨ Features

- One-click VPS deployment via Docker containers  
- Interactive Discord slash commands for all management tasks  
- Live resource stats: CPU, RAM, and disk usage  
- Dynamic `/help` with categorized sections (User / Admin / Super)  
- GUI management with buttons (`/manage_vps`)  
- Role-based access: User, Admin, and Super User  
- Automatic systemd service installer  
- Real-time logging and analytics  

---

## 🖥️ Supported OS Images

- 🐧 Ubuntu  
- 🦕 Debian  
- ⛰️ Alpine Linux  
- 🎯 Arch Linux  
- 💣 Kali Linux  
- 🎩 Fedora  

> Docker images are automatically built if their Dockerfiles exist.

---

## ⚙️ Requirements

- Debian or Ubuntu (with `apt` package manager)  
- Docker & systemd installed and running  
- Python 3.8+ and `pip3`  
- Root or sudo privileges  

---

## ⚡ Quick Installation

Run the official **Gp TEAM** installation script:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vps-deploy-bot/main/install.sh)
```

The script will:
- Update your system  
- Install dependencies  
- Clone the official repo  
- Build Docker images (if available)  
- Configure `bot.py` automatically  
- Optionally create and start a systemd service  

### During setup, you’ll be asked for:
- **Discord Bot Token**  
- **Logs Channel ID**  
- **Admin Role ID**  
- (Optional) RAM and server limits  

---

## 🧩 Manual Installation

```bash
sudo apt update -y && sudo apt install -y git docker.io python3-pip
sudo systemctl enable --now docker

sudo git clone https://github.com/gpteamofficial/vps-deploy-bot.git /opt/vps-deploy-bot
cd /opt/vps-deploy-bot

# Python dependencies
sudo pip3 install --upgrade pip
[ -f requirements.txt ] && sudo pip3 install -r requirements.txt || sudo pip3 install discord.py docker psutil

# Build Docker images
[ -f Dockerfile.debian ] && sudo docker build -t debian-vps -f Dockerfile.debian .
[ -f Dockerfile.ubuntu ] && sudo docker build -t ubuntu-vps -f Dockerfile.ubuntu .

# Run manually
python3 bot.py
```

---

## 💡 Example Usage

| Command | Description |
|----------|--------------|
| `/deploy user:@User os:ubuntu` | Deploy a new VPS for a user |
| `/start <id>` | Start your VPS |
| `/stop <id>` | Stop your VPS |
| `/restart <id>` | Restart your VPS |
| `/regen-ssh <id>` | Regenerate SSH access |
| `/transfer_vps <id> @NewUser` | Transfer ownership |
| `/top_usage metric:ram limit:10` | View top RAM users (Admin) |
| `/resources` | View host resource usage |
| `/help` | Display the categorized help menu |

---

## 🧠 Configuration

The installer automatically generates a `.env` file and updates `bot.py`:

```env
TOKEN=<your_bot_token>
LOGS_CHANNEL_ID=<your_logs_channel_id>
ADMIN_ROLE_ID=<your_admin_role_id>
RAM_LIMIT=2g
SERVER_LIMIT=12
```

Systemd service (optional) is created as:

```bash
sudo systemctl status vps-bot
sudo journalctl -u vps-bot -f
```

---

## 🧰 Troubleshooting

| Issue | Solution |
|--------|-----------|
| Commands not visible | Ensure the bot has permissions and slash commands synced |
| No DM messages | Check Discord privacy settings |
| Docker build fails | Verify Docker is running and files exist |
| Service won’t start | View logs with `journalctl -u vps-bot -n 100` |

---

## 🤝 Credits

**Developed & maintained by:**  
**Gp TEAM**

**Acknowledgements:**  

---

## 📜 License

Licensed under the **MIT License**.  
See [LICENSE](./LICENSE) for more information.
