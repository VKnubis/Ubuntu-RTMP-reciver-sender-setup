# Nginx RTMP Server Setup

This folder is a GitHub-ready setup package for a fresh Ubuntu/Debian server,
but it is also careful on servers where Nginx already exists. Copy it to a VPS,
run one script, and it will install or reuse Nginx, add RTMP streaming, and
install the same dashboard website from this server.

It sets up:

- RTMP ingest on port `1935`
- Live app name: `live`
- HLS output under `/var/www/html/hls`
- Browser stats endpoint at `/stat`
- Optional web dashboard at `/panel.html`

The setup is based on an Ubuntu Nginx layout:

- Nginx config: `/etc/nginx/nginx.conf`
- RTMP include folder: `/etc/nginx/rtmp.d`
- Dashboard HTTP config: `/etc/nginx/conf.d/rtmp-panel.conf`
- Web root: `/var/www/html`
- Nginx logs: `/var/log/nginx/access.log` and `/var/log/nginx/error.log`

## Requirements

Use Ubuntu/Debian with sudo access. The setup script installs Nginx and the RTMP
module if they are missing.

## Files

```text
configs/rtmp-live.conf    Managed RTMP live app config
configs/rtmp-panel.conf   HTTP server for /stat, HLS, and the dashboard
web/panel.html            RTMP dashboard
web/stat.xsl              Optional RTMP stats stylesheet
setup.sh                  Main installer entrypoint
scripts/install.sh        Helper script to copy files into place
```

## Upload to GitHub

If Git is not installed yet:

```bash
sudo apt update
sudo apt install git
```

Create a new empty repo on GitHub, then run:

```bash
git init
git add .
git commit -m "Add fresh Nginx RTMP server setup"
git branch -M main
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

## Install

From this repo folder:

```bash
chmod +x setup.sh scripts/install.sh
sudo ./setup.sh
```

The script will:

- Install `nginx` and `libnginx-mod-rtmp`
- Reuse existing Nginx if it is already installed
- Back up touched config files with a timestamp
- Add `/etc/nginx/rtmp.d/*.conf` to `nginx.conf` only when no RTMP block exists
- Leave an existing RTMP block alone so it does not break current streams
- Copy the dashboard config into `/etc/nginx/conf.d/rtmp-panel.conf`
- Copy `panel.html` and `stat.xsl` into `/var/www/html`
- Create `/var/www/html/hls`
- Open ports `1935` and `8080` when UFW is active
- Test and reload Nginx

After it finishes, it prints your publish URL, HLS URL, dashboard URL, and
stats URL.

## Existing Nginx Behavior

The installer is conservative:

- If Nginx is missing, it installs it.
- If Nginx already exists, it keeps your current config and only adds managed files.
- If `/etc/nginx/nginx.conf` already has an `rtmp { ... }` block, the script does not add a second one.
- If there is no RTMP block, the script adds `include /etc/nginx/rtmp.d/*.conf;` at the top level and installs `configs/rtmp-live.conf`.

If you already have a custom RTMP block, make sure it includes this app:

```nginx
application live {
    live on;
    record off;
    wait_key on;
    hls on;
    hls_path /var/www/html/hls;
    hls_fragment 2s;
    hls_playlist_length 10s;
    hls_cleanup on;
}
```

## Manual Install

Back up your current config first:

```bash
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
```

Install the RTMP include:

```bash
sudo mkdir -p /etc/nginx/rtmp.d
sudo cp configs/rtmp-live.conf /etc/nginx/rtmp.d/live.conf
echo 'include /etc/nginx/rtmp.d/*.conf;' | sudo tee -a /etc/nginx/nginx.conf
sudo cp configs/rtmp-panel.conf /etc/nginx/conf.d/rtmp-panel.conf
```

Copy the dashboard files:

```bash
sudo cp web/panel.html /var/www/html/panel.html
sudo cp web/stat.xsl /var/www/html/stat.xsl
sudo mkdir -p /var/www/html/hls
sudo chown -R www-data:www-data /var/www/html/hls
```

Test and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Firewall

Open the RTMP and dashboard ports if your firewall is enabled:

```bash
sudo ufw allow 1935/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```

If you serve the dashboard on normal HTTP instead, open port `80`.

## Stream With OBS

In OBS, open `Settings > Stream` and use:

```text
Service: Custom
Server: rtmp://YOUR_SERVER_IP/live
Stream Key: mystream
```

Your RTMP publish URL becomes:

```text
rtmp://YOUR_SERVER_IP/live/mystream
```

## Watch the Stream

RTMP playback URL:

```text
rtmp://YOUR_SERVER_IP/live/mystream
```

HLS playback URL:

```text
http://YOUR_SERVER_IP:8080/hls/mystream.m3u8
```

Dashboard:

```text
http://YOUR_SERVER_IP:8080/panel.html
```

Stats XML:

```text
http://YOUR_SERVER_IP:8080/stat
```

## Test With FFmpeg

Publish a local video file:

```bash
ffmpeg -re -i video.mp4 -c copy -f flv rtmp://YOUR_SERVER_IP/live/mystream
```

Publish a test pattern:

```bash
ffmpeg -re -f lavfi -i testsrc=size=1280x720:rate=30 -f lavfi -i sine=frequency=1000 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -f flv \
  rtmp://YOUR_SERVER_IP/live/mystream
```

## Troubleshooting

Check config syntax:

```bash
sudo nginx -t
```

Check service status:

```bash
systemctl status nginx
```

Watch logs:

```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

Confirm Nginx is listening:

```bash
sudo ss -tulpn | grep nginx
```

Common fixes:

- If OBS cannot connect, check port `1935` and your firewall/security group.
- If `/stat` returns 404, confirm `configs/rtmp-panel.conf` is copied to `/etc/nginx/conf.d/rtmp-panel.conf`.
- If HLS files do not appear, confirm `/var/www/html/hls` exists and is writable by `www-data`.
- If `nginx -t` says `unknown directive "rtmp"`, install `libnginx-mod-rtmp`.

## Security Notes

This basic setup is open to anyone who can reach port `1935`. For production, add protections such as:

- Firewall rules limiting who can publish
- A secret stream key
- `allow publish` / `deny publish` rules in the RTMP app
- HTTPS for the dashboard
- Basic auth or IP restrictions for `/stat` and `/panel.html`
