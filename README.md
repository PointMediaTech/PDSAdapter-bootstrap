# PDSAdapter-bootstrap

PDS 轉接器的引導安裝腳本。在站點的主機上執行 `install.sh`,會從 GHCR 拉映像、做初始設定,然後啟動轉接器。之後要更新或退版,也是重跑同一支腳本。

PDS 轉接器會把 CueTone(或 cuetoneweb)送出的 UDP 廣告狀態,轉成 encoder 的 SCTE-35 `out` / `in` 命令。

> **注意:這個 repo 雖然公開,但只放安裝腳本。** 轉接器的映像是 private,安裝時腳本會請你輸入 GitHub 帳號與 token,帳號要有 `PointMediaTech/PDSAdapter` 的讀取權限才拉得到映像。沒有權限的帳號下載得到腳本,但裝不起來。帳號與 token 的要求見下面「事前準備」。

## 為什麼要另外放一個 repo

- 轉接器的原始碼 repo `PointMediaTech/PDSAdapter` 和映像 `ghcr.io/pointmediatech/point-pdsadapter` 都是 private。站點主機上沒有原始碼,也沒有 GitHub 憑證。
- `PDSAdapter-bootstrap` 是公開的,只放安裝腳本,任何主機都能用 `curl` 下載,不用登入。
- 腳本裡沒有帳號、token 或其他秘密。安裝時才請你輸入 GitHub 帳號與 token 拉映像,用完就刪,不會留在主機上。
- 安裝方式與 `cuetoneweb-bootstrap` 相同,站點的工程師只要學一套步驟。

## 事前準備

| 項目 | 要求 |
|---|---|
| 作業系統 | Ubuntu;沒有 Docker 時,腳本會自動安裝 `docker.io` 與 `docker-compose-v2`。其他發行版要先自行安裝 Docker 與 docker compose |
| 架構 | amd64 或 arm64,`docker pull` 會自動選對架構 |
| 網路 | 能連 `raw.githubusercontent.com` 與 `ghcr.io`;要自動安裝 Docker 時,還要能連 Ubuntu 套件來源 |
| 權限 | 能用 `sudo` |
| 終端 | 腳本會詢問帳密與設定,要在互動式終端執行(現場操作或 SSH 登入後) |
| port | 網頁預設 8090,被占用時安裝過程會請你改用其他 port |
| GitHub | 帳號要有 `PointMediaTech/PDSAdapter` 的讀取權限。到 Settings → Developer settings → Personal access tokens → Tokens (classic) 建一個 token,只勾 `read:packages`,期限設短 |

確認連得到 GHCR(回 `401` 就代表連得到):

```bash
curl -sI https://ghcr.io/v2/ | head -1
```

## 安裝

登入要安裝的主機(現場操作或 SSH),執行:

```bash
# 先下載再執行:腳本要從終端讀 GitHub 帳密,不能用 curl | bash
curl -fsSL https://raw.githubusercontent.com/PointMediaTech/PDSAdapter-bootstrap/main/install.sh -o install.sh
sudo bash install.sh
```

| 參數 | 說明 |
|---|---|
| `--version X` | 映像 tag,預設 `latest`;例如 `1.1.0` |
| `--from 目錄` | 沿用舊安裝的資料庫(encoder 主機、金鑰、對應、命令記錄),例如 `--from /srv/pdsadapter`。舊容器要先停止並移除 |

執行過程會詢問:

1. GitHub 帳號與 token。
2. 只有新設備會問:網頁 port 與管理密碼(輸入兩次)。port 已被占用時,會建議一個空的 port。

初始設定結束時會印出網址(預設 `http://<主機>:8090`)。最後出現 `完成:… 已啟動` 後,用瀏覽器開這個網址,以管理密碼登入。

## 腳本會對主機做什麼

腳本要用 `sudo` 執行,以下是它會做的事:

1. 沒有 Docker 或 docker compose 時,用 apt 安裝(只有 Ubuntu 會自動安裝)。
2. 檢查舊安裝。這台已有其他方式裝的 `pds-adapter` 容器,或是舊版腳本的安裝目錄時,會印出要先執行的指令並停下來,不會動到舊安裝。
3. 建立系統帳號 `pdsadapter`(不能登入)與目錄 `/opt/pds-adapter`。容器以這個帳號執行。
4. 登入 GHCR,拉指定版本的映像。憑證只放在 `/run/pds-adapter/docker`(tmpfs),腳本結束時一定會刪除,不需要 `docker logout`。
5. 新設備:在容器裡跑初始設定,產生 `/opt/pds-adapter/.env` 與 `compose.yaml`。有 `--from` 時,先把舊資料庫複製過來。已安裝的設備跳過這一步。
6. 把 `compose.yaml` 的映像換成這次的版本,再用 `docker compose up -d` 啟動。

設定檔與資料庫都放在 `/opt/pds-adapter`。

## 更新與退版

重新下載並執行同一支腳本。一樣要輸入 GitHub 帳號與 token,但已安裝的設備不會再詢問設定,只會換映像版本並重新啟動,轉接器會中斷數秒:

```bash
curl -fsSL https://raw.githubusercontent.com/PointMediaTech/PDSAdapter-bootstrap/main/install.sh -o install.sh
sudo bash install.sh                    # 更新到最新版
sudo bash install.sh --version 1.1.0    # 退回某一版
```

## 安裝之後

第一次設定(encoder 金鑰、來源、對應)、日常指令與移除步驟,請看 [PDSAdapter 的 README](https://github.com/PointMediaTech/PDSAdapter#readme) 的「新設備安裝(GHCR 映像)」一節。那個 repo 是 private,要用有權限的 GitHub 帳號登入才看得到。

## 維護

`PDSAdapter-bootstrap` 的 `install.sh` 與 `README.md`,原始檔是 `PDSAdapter` 的 `deploy/install.sh` 與 `deploy/README.md`。要修改就改原始檔,再把同一份複製過來,不要直接在 `PDSAdapter-bootstrap` 改。
