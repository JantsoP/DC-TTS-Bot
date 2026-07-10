# TTS Bot - Rust Rewrite

Text to speech Discord bot using Serenity, Songbird, and Poise.

This guide covers full self-hosting with Docker, including required credentials, API keys, and premium activation.

## What Runs

This deployment has 3 services:

- `bot` (this repository)
- `database` (PostgreSQL)
- `tts-service` (https://github.com/Discord-TTS/tts-service)

The bot calls `tts-service` for voice generation over HTTP/WebSocket.

## Credentials And Keys Checklist

### Required

1. Discord Bot Token
2. Discord IDs:
	- Main/support server ID
	- Announcements channel ID
	- Invite channel ID
	- OFS role ID
3. Discord webhook URLs:
	- Logs webhook
	- Errors webhook
4. PostgreSQL credentials:
	- Database name
	- Username
	- Password
5. Google Cloud service account JSON for Text-to-Speech API

### Optional

1. AWS Polly credentials (only if you want Polly mode in `tts-service`):
	- `AWS_REGION`
	- `AWS_ACCESS_KEY_ID`
	- `AWS_SECRET_ACCESS_KEY`
2. DeepL API key (only if you want translation in `tts-service`):
	- `DEEPL_KEY`
3. Premium monetization config in bot `config.toml` (`[Premium-Info]`)

## Google Cloud Setup (Required For gCloud Mode)

1. Create or select a Google Cloud project.
2. Enable Cloud Text-to-Speech API.
3. Enable billing for the project.
4. Create a service account.
5. Grant it access to Text-to-Speech (project-level editor also works, but least-privilege is preferred).
6. Create and download a JSON key for the service account.
7. Place the JSON on the server, for example: `/opt/dc-tts/gcp.json`.

`tts-service` reads this JSON from `GOOGLE_APPLICATION_CREDENTIALS`.

## AlmaLinux Docker Setup

Run on AlmaLinux 9:

```bash
sudo dnf install -y dnf-plugins-core git
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

## Clone And Prepare Files

```bash
git clone https://github.com/Discord-TTS/Bot.git
cd Bot
cp config-docker.toml config.toml
cp docker-compose-example.yml docker-compose.yml
```

## Configure `config.toml`

Update `config.toml` with your values.

Example complete shape:

```toml
[Main]
log_level = "info"
website_url = "https://example.com"
main_server_invite = "https://discord.gg/example"
announcements_channel = 123456789012345678
invite_channel = 123456789012345678
main_server = 123456789012345678
ofs_role = 123456789012345678
token = "DISCORD_BOT_TOKEN"

[[TTS-Services]]
url = "http://localhost:20310"
weight = 1

[PostgreSQL-Info]
database = "tts"
password = "tts_password"
host = "localhost"
user = "tts"

[Webhook-Info]
logs = "https://discord.com/api/webhooks/..."
errors = "https://discord.com/api/webhooks/..."

# Optional website stats updater
#[Website-Info]
#url = "https://example.com"
#stats_key = "secret"

# Optional premium monetization integration.
# If omitted, self-hosting premium checks are treated as valid for local activation flow.
#[Premium-Info]
#discord_monetisation_enabled = false
#patreon_page_url = "https://patreon.com/..."
#patreon_service = "https://premium-service.example"
#basic_sku = 0
#extra_sku = 0

# Optional bot-list integrations
#[Bot-List-Tokens]
#top_gg = "..."
#discord_bots_gg = "..."
#bots_on_discord = "..."
```

## Configure `docker-compose.yml`

Update compose values:

1. Set bot image to locally built image.
2. Set `GOOGLE_APPLICATION_CREDENTIALS` host path for your JSON.
3. Optionally set AWS/DeepL env vars for `tts-service`.

Create a `.env` file in the same folder as `docker-compose.yml` so compose can resolve
`${GOOGLE_APPLICATION_CREDENTIALS}` in the bind mount:

```bash
cat > .env << 'EOF'
GOOGLE_APPLICATION_CREDENTIALS=/opt/dc-tts/gcp.json
EOF
```

You can also `export GOOGLE_APPLICATION_CREDENTIALS=/opt/dc-tts/gcp.json` in your shell,
but `.env` is preferred for repeatable restarts.

Example:

```yaml
services:
  bot:
	 image: discord-tts-bot:local
	 volumes:
		- type: bind
		  source: ./config.toml
		  target: /bot/config.toml
		  # Add :Z on SELinux systems if needed
	 depends_on: [database, tts-service]
	 network_mode: "host"

  database:
	 image: postgres:13
	 ports: ["5432:5432"]
	 environment:
		POSTGRES_USER: tts
		POSTGRES_PASSWORD: tts_password
		POSTGRES_DB: tts

  tts-service:
	 image: gnomeddev/tts-service
	 volumes:
		- type: bind
		  source: /opt/dc-tts/gcp.json
		  target: /gcp.json
		  # Add :Z on SELinux systems if needed
	 environment:
		- IPV6_BLOCK=DISABLE
		- LOG_LEVEL=INFO
		- BIND_ADDR=0.0.0.0:20310
		- GOOGLE_APPLICATION_CREDENTIALS=/gcp.json
		# Optional Polly support
		# - AWS_REGION=eu-west-1
		# - AWS_ACCESS_KEY_ID=...
		# - AWS_SECRET_ACCESS_KEY=...
		# Optional DeepL translation
		# - DEEPL_KEY=...
	 network_mode: "host"
	 expose: ["20310"]
```

## Build And Start

The compose file uses `image: discord-tts-bot:local` for the bot service.
That means you must build a local image with the same tag before running compose.

```bash
docker build -t discord-tts-bot:local .
docker compose up -d
docker compose logs -f bot
```

Alternative (compose-managed build):

1. Change the bot service in `docker-compose.yml` to use a build block.
2. Keep or set an explicit local image tag.

Example:

```yaml
services:
	bot:
		build: .
		image: discord-tts-bot:local
```

Then start with:

```bash
docker compose up --build -d
```

If SELinux blocks bind mounts on AlmaLinux, use `:Z` bind options.

## Verify Bot Startup

1. Bot logs should show DB migration/startup and shard startup.
2. No errors when fetching voices from `tts-service`.
3. Invite bot to server and run setup/join commands.

## Register Slash Commands

This bot does not auto-register slash commands on startup.
You must run the owner-only prefix command once:

```text
-register
```

Notes:

1. The default prefix is `-`.
2. The command is owner-only, so run it from the bot owner account.
3. The current implementation registers global commands, so command visibility can take some time to propagate.

## Premium Features On Self-Hosted Instance

### How it works

Premium commands require the guild to be linked to a `premium_user`.

The normal user-facing flow is:

1. In target server, run `/premium activate` from the account you want linked.
2. Bot records that user as `premium_user` for the guild.
3. Premium modes/features unlock for that guild.

To restrict who can switch to premium modes with `/set mode`, set a dedicated role:

```text
/set mode_required_role @RoleName
```

Only that role (and server admins) can select premium voice modes afterwards.

### Self-host shortcut behavior

If you do not configure `[Premium-Info]`, the self-host flow treats premium entitlement checks as valid for activation. This simplifies local/private deployments.

### If you configure real premium integration

Then `/premium activate` requires an actual entitlement (Patreon/Discord monetization path configured in `[Premium-Info]`).

## Troubleshooting

1. `No TTS services are configured`:
	- Add at least one `[[TTS-Services]]` block to `config.toml`.
2. Bot cannot fetch voices:
	- Ensure `tts-service` is running and reachable on `20310`.
3. `tts-service` exits with `IPV6_BLOCK not set`:
	- Set `IPV6_BLOCK=DISABLE` in the `tts-service` environment section.
4. Bot exits with `GLIBC_2.38 not found`:
	- Rebuild the bot image after pulling latest Dockerfile changes.
	- Run `docker compose down` then `docker build -t discord-tts-bot:local .` and `docker compose up -d`.
5. gCloud voice failures:
	- Verify service account JSON path and Text-to-Speech API enabled.
6. Premium activate says not subscribed:
	- Omit `[Premium-Info]` for local self-host behavior, or configure real premium service correctly.
