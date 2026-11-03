#!/usr/bin/env bash
# PDS 轉接器引導安裝:從 GHCR 拉映像,新機執行初始設定,再以 docker compose 啟動。不含任何秘密。做法與 cuetoneweb 相同。
# 原始檔是 PDSAdapter 的 deploy/install.sh,同一份複製到公開 repo PointMediaTech/PDSAdapter-bootstrap(主 repo 是 private,現場拿不到)。
# 先下載再執行(要從終端讀帳密,不能 curl | bash):
#   curl -fsSL https://raw.githubusercontent.com/PointMediaTech/PDSAdapter-bootstrap/main/install.sh -o install.sh
#   sudo bash install.sh [--version X] [--from 舊資料目錄]
# 安裝、更新、退版都用它;已安裝的機器不會再詢問設定,只換映像版本並重新啟動。
set -euo pipefail
IMAGE=ghcr.io/pointmediatech/point-pdsadapter
DIR=/opt/pds-adapter
NAME=pds-adapter

version=latest
from=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) version=$2; shift 2 ;;
        --from) from=$2; shift 2 ;;
        *) echo "不認得的參數:$1" >&2; exit 1 ;;
    esac
done
if [[ $EUID -ne 0 ]]; then echo "請用 sudo 執行" >&2; exit 1; fi
if [[ -n $from ]]; then
    if [[ ! -f $from/pds.sqlite ]]; then echo "找不到舊的資料庫:$from/pds.sqlite" >&2; exit 1; fi
    if [[ -e $DIR/pds.sqlite ]]; then echo "$DIR/pds.sqlite 已存在(已經搬過了),不要再加 --from" >&2; exit 1; fi
fi

need=()
if ! command -v docker >/dev/null; then need+=(docker.io docker-compose-v2)
elif ! docker compose version >/dev/null 2>&1; then need+=(docker-compose-v2); fi
if (( ${#need[@]} )); then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ $ID != ubuntu ]]; then echo "請先安裝 Docker 與 docker compose(只有 Ubuntu 會自動安裝)" >&2; exit 1; fi
    # </dev/null:不讓 apt 讀走使用者先打的帳號
    apt-get update -q </dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-upgrade "${need[@]}" </dev/null
    systemctl enable --now docker
fi

# 2026-10-28 第一版 install.sh 也裝在這裡(docker-compose.yml、root 的 .env、資料在 /srv/pdsadapter),要先移開
if [[ -f $DIR/docker-compose.yml ]]; then
    echo "$DIR 是舊版 install.sh 裝的,請先執行:cd $DIR && sudo docker compose down && sudo mv $DIR $DIR.old" >&2
    echo "再加 --from /srv/pdsadapter 重新安裝,沿用舊資料" >&2
    exit 1
fi
# 用原始碼 build 或其他方式裝的 pds-adapter 容器:名稱相同會衝突,--from 的舊資料也要等它停掉才完整
if old=$(docker container inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$NAME" 2>/dev/null) &&
   [[ $old != "$DIR" ]]; then
    echo "這台已有 $NAME 容器(來自 ${old:-不明目錄}),請先停止並移除:cd ${old:-<目錄>} && sudo docker compose down" >&2
    exit 1
fi

# 容器以系統帳號 pdsadapter 執行,資料目錄的擁有者也是它,資料庫才寫得進去
id -u pdsadapter >/dev/null 2>&1 || useradd --system --user-group --no-create-home --shell /usr/sbin/nologin pdsadapter
install -d -o pdsadapter -g pdsadapter -m 755 "$DIR"
uid=$(id -u pdsadapter) gid=$(id -g pdsadapter)

# GHCR 憑證只放在記憶體檔案系統,結束時一定刪除,機器上不留
export DOCKER_CONFIG=/run/pds-adapter/docker
mkdir -p "$DOCKER_CONFIG"
chmod 700 "$DOCKER_CONFIG"
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
read -r -p "GitHub 帳號:" user
read -r -s -p "GitHub token(read:packages):" token
echo
printf '%s' "$token" | docker login ghcr.io -u "$user" --password-stdin >/dev/null
unset token

img=$IMAGE:$version
docker pull --quiet "$img" >/dev/null

# compose.yaml 是 setup 最後才寫的,有它就代表已完成初始設定
if [[ ! -f $DIR/compose.yaml ]]; then
    if [[ -n $from ]]; then
        # SQLite 是 WAL 模式,-wal 要一起複製;舊容器已確認不在了
        cp -p "$from"/pds.sqlite* "$DIR/"
        chown "$uid:$gid" "$DIR"/pds.sqlite*
    fi
    # 用 host 網路才偵測得到主機上已使用的 port
    docker run --rm -it --network host --user "$uid:$gid" -v "$DIR:/data" "$img" python -m pdsadapter.setup
fi
sed -i "s|^\( *image:\).*|\1 $img|" "$DIR/compose.yaml"
docker compose -f "$DIR/compose.yaml" up -d
echo "完成:$img 已啟動"
