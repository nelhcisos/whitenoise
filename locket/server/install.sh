#!/usr/bin/env bash
# Locket server: one-command install on a fresh Ubuntu (24.04 recommended) or Debian VPS.
#
#   curl -fsSL https://raw.githubusercontent.com/nelhcisos/whitenoise/claude/locket-friends-app/locket/server/install.sh | sudo bash
#
# Run the same command again to update. Data (database and photos) is kept.
# To answer the setup questions again: add LOCKET_RECONFIGURE=1 before "bash".
set -euo pipefail

REPO="${LOCKET_REPO:-https://github.com/nelhcisos/whitenoise.git}"
BRANCH="${LOCKET_BRANCH:-claude/locket-friends-app}"
SRC="${LOCKET_DIR:-/opt/locket}"
SERVER="$SRC/locket/server"

say() { printf '\n\033[1;33m%s\033[0m\n' "$*"; }
ask() {
  local answer
  read -r -p "$1" answer < /dev/tty
  printf '%s' "$answer"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Запусти с sudo: curl -fsSL … | sudo bash"
  exit 1
fi

if ! command -v docker > /dev/null || ! docker compose version > /dev/null 2>&1; then
  say "Ставлю Docker…"
  apt-get update -qq
  apt-get install -y -qq docker.io docker-compose-v2 > /dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker > /dev/null 2>&1 || true
fi
command -v git > /dev/null || apt-get install -y -qq git > /dev/null

if [ -d "$SRC/.git" ]; then
  say "Обновляю Locket…"
  git -C "$SRC" fetch -q --depth 1 origin "$BRANCH"
  git -C "$SRC" reset -q --hard FETCH_HEAD
else
  say "Скачиваю Locket…"
  git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$SRC"
fi
cd "$SERVER"

if [ "${LOCKET_RECONFIGURE:-}" = "1" ]; then rm -f .env; fi

if [ ! -f .env ]; then
  ip="$(curl -fsS4 https://api.ipify.org || curl -fsS4 https://ifconfig.me)"
  default_domain="$(echo "$ip" | tr . -).sslip.io"
  say "Настройка (один раз)"
  echo "Адрес сервера. Своего домена нет — просто нажми Enter, подойдёт бесплатный $default_domain."
  domain="$(ask "Домен [$default_domain]: ")"
  domain="${domain:-$default_domain}"

  echo
  echo "Ключ для пуш-уведомлений Apple (developer.apple.com → Keys)."
  echo "Можно пропустить (Enter) — тогда сервер работает, но пуши не шлёт."
  key_id="$(ask "Key ID ключа APNs, 10 символов: ")"
  apns=""
  if [ -n "$key_id" ]; then
    team_id="$(ask "Team ID, 10 символов: ")"
    bundle_id="$(ask "Bundle ID приложения (как в секрете LOCKET_BUNDLE_ID): ")"
    echo "Открой файл AuthKey_${key_id}.p8, скопируй всё содержимое (вместе со строками BEGIN и END), вставь сюда и нажми Enter:"
    mkdir -p secrets
    : > secrets/AuthKey.p8
    while IFS= read -r line < /dev/tty; do
      printf '%s\n' "$line" >> secrets/AuthKey.p8
      case "$line" in *"END PRIVATE KEY"*) break ;; esac
    done
    chmod 600 secrets/AuthKey.p8
    apns="APNS_KEY_PATH=/secrets/AuthKey.p8
APNS_KEY_ID=$key_id
APNS_TEAM_ID=$team_id
APNS_TOPIC=$bundle_id"
  fi

  cat > .env << EOF
DOMAIN=$domain
PUBLIC_URL=https://$domain
$apns
# Results every Sunday at 21:00 Moscow time (UTC+3), reminder 3 hours before
TZ_OFFSET_MINUTES=180
WEEK_END_DAY=7
WEEK_END_HOUR=21
REMINDER_HOURS_BEFORE=3
EOF
  chmod 600 .env
fi

domain="$(grep '^DOMAIN=' .env | cut -d= -f2)"

if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp > /dev/null
  ufw allow 443/tcp > /dev/null
fi

say "Запускаю…"
docker compose up -d --build

printf 'Жду, пока поднимется https://%s ' "$domain"
for _ in $(seq 1 60); do
  if curl -fsS "https://$domain/health" > /dev/null 2>&1; then
    say "Готово! Адрес сервера: https://$domain"
    echo "Впиши его в GitHub-секрет LOCKET_API_URL (см. locket/README.md)."
    exit 0
  fi
  printf '.'
  sleep 5
done
echo
echo "Сервер запущен, но https://$domain пока не отвечает. Проверь, что порты 80 и 443 открыты у хостинга,"
echo "и посмотри журнал: cd $SERVER && docker compose logs --tail 50"
exit 1
