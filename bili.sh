#!/usr/bin/env bash

# set -Eeo pipefail
# IFS=$'\n\t'
set -e


# ================= Bili-Term - B站终端客户端 =================
# 版本: 0.1.0
# 作者: akirco
# 描述: 终端中的B站客户端，支持视频播放、UP主搜索、历史记录等功能
# ============================================================

# ---------------------------------------------------------------------------- #
#                                     配置相关                                   #
# ---------------------------------------------------------------------------- #

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# 配置文件路径
CONFIG_DIR="$XDG_CONFIG_HOME/bili-term"
CONFIG_FILE="$CONFIG_DIR/config"
COOKIE_FILE="$CONFIG_DIR/cookies.txt"


# 缓存目录
CACHE_BASE_DIR="$XDG_CACHE_HOME/bili-term"
CACHE_DIR="$CACHE_BASE_DIR/$$"  # 使用PID作为临时目录
LOG_FILE="./bili-term.log"

mkdir -p "$CACHE_DIR"

DOWNLOAD_DIR="$HOME/Videos/bilibili/downloads"
mkdir -p "$DOWNLOAD_DIR"

DEFAULT_CONFIG="# Bili-Term 配置文件
# 用户代理
USER_AGENT=\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\"

# 下载目录
DOWNLOAD_DIR=\"$DOWNLOAD_DIR\"

# 播放器设置
VIDEO_PLAYER=\"mpv\"
PLAYER_ARGS=\"--no-border --ontop --geometry=960x540+50+50\"

# 下载设置
DOWNLOAD_FORMAT=\"bestvideo[height<=1080]+bestaudio/best[height<=1080]\"
DOWNLOAD_THREADS=4

# 界面设置
ENABLE_PREVIEW=true
PREVIEW_WIDTH=50%
PREVIEW_HEIGHT=20
SHOW_STATISTICS=true
COLOR_SCHEME=\"default\"
FZF_COLOR=\"bg+:#101115,bg:#0E1011,fg:#c0caf5,hl:#bb9af7,fg+:#c0caf5,hl+:#bb9af7,info:#7dcfff,prompt:#7aa2f7,pointer:#bb9af7,marker:#bb9af7,spinner:#7dcfff,header:#bb9af7\"

# 缓存设置
CACHE_DURATION=3600  # 缓存时间（秒）

# API设置
API_TIMEOUT=10
API_RETRY=2

# 搜索设置
SEARCH_PAGE_SIZE=20
SEARCH_MAX_RESULTS=100
RECOMMEND_PAGE_SIZE=20
POPULAR_PAGE_SIZE=20
PERSONAL_PAGE_SIZE=20
VIDEO_DETAIL_PAGE_SIZE=1
UP_DETAIL_PAGE_SIZE=1


# 快捷键设置
KEY_PLAY=\"enter\"
KEY_PLAY_ALL=\"alt-enter\"
KEY_DOWNLOAD=\"ctrl-d\"
KEY_REFRESH=\"ctrl-r\"
KEY_BACK=\"esc\"

# 代理设置（如需）
# HTTP_PROXY=\"http://127.0.0.1:1080\"
# HTTPS_PROXY=\"http://127.0.0.1:1080\"
"

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$CONFIG_DIR"
        echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"
        echo -e "${GREEN}已创建默认配置文件: $CONFIG_FILE${NC}"
    fi

    if [ -f "$CONFIG_FILE" ]; then
      if ! source "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${RED}配置文件语法错误，使用默认配置${NC}"
      fi
    fi

    USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36}"
    DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/Videos/bilibili/downloads}"
    VIDEO_PLAYER="${VIDEO_PLAYER:-mpv}"
    ENABLE_PREVIEW="${ENABLE_PREVIEW:-true}"
    SHOW_STATISTICS="${SHOW_STATISTICS:-true}"
    SEARCH_PAGE_SIZE="${SEARCH_PAGE_SIZE:-20}"
    RECOMMEND_PAGE_SIZE="${RECOMMEND_PAGE_SIZE:-20}"
    POPULAR_PAGE_SIZE="${POPULAR_PAGE_SIZE:-20}"
    PERSONAL_PAGE_SIZE="${PERSONAL_PAGE_SIZE:-20}"
    VIDEO_DETAIL_PAGE_SIZE="${VIDEO_DETAIL_PAGE_SIZE:-1}"
    UP_DETAIL_PAGE_SIZE="${UP_DETAIL_PAGE_SIZE:-1}"
    API_TIMEOUT="${API_TIMEOUT:-10}"

    mkdir -p "$DOWNLOAD_DIR"
    mkdir -p "$CACHE_BASE_DIR"

    if [ -z "$FZF_COLOR" ]; then
        FZF_COLOR="bg+:#101115,bg:#0E1011,fg:#c0caf5,hl:#bb9af7,fg+:#c0caf5,hl+:#bb9af7,info:#7dcfff,prompt:#7aa2f7,pointer:#bb9af7,marker:#bb9af7,spinner:#7dcfff,header:#bb9af7"
    fi
}

# ---------------------------------------------------------------------------- #
#                                      初始化                                     #
# ---------------------------------------------------------------------------- #

# ----------------------------------- 颜色定义 ----------------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
# ORANGE='\033[0;33m'
# MAGENTA='\033[1;35m'
NC='\033[0m'


load_config

if [ -n "$HTTP_PROXY" ]; then
    export http_proxy="$HTTP_PROXY"
    export HTTP_PROXY="$HTTP_PROXY"
fi
if [ -n "$HTTPS_PROXY" ]; then
    export https_proxy="$HTTPS_PROXY"
    export HTTPS_PROXY="$HTTPS_PROXY"
fi

trap 'cleanup' EXIT INT TERM

cleanup() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "$CACHE_DIR" 2>/dev/null
    fi
}


# ---------------------------------------------------------------------------- #
#                                     工具函数                                     #
# ---------------------------------------------------------------------------- #
check_dependency() {
    local missing=()
    local required=("curl" "jq" "fzf" "chafa" "mpv" "yt-dlp" "qrencode")

    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}错误: 缺少必要的依赖:${NC}"
        for cmd in "${missing[@]}"; do
            echo -e "  ${YELLOW}- $cmd${NC}"
        done
        exit 1
    fi
}



urlencode() {
    echo -n "$1" | jq -sRr @uri
}

timestamp_to_date() {
    local timestamp="$1"
    if [ -n "$timestamp" ] && [ "$timestamp" != "null" ] && [ "$timestamp" -gt 0 ]; then
        date -d "@$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || \
        date -r "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || \
        echo "$timestamp"
    else
        echo "未知"
    fi
}

format_number() {
    local num="$1"
    if [ -n "$num" ] && [ "$num" != "null" ]; then
        if [ "$num" -ge 100000000 ]; then
            local yi=$((num / 100000000))
            local remainder=$((num % 100000000))
            local decimal=$((remainder * 10 / 100000000))
            echo "${yi}.${decimal}亿"
        elif [ "$num" -ge 10000 ]; then
            local wan=$((num / 10000))
            local remainder=$((num % 10000))
            local decimal=$((remainder * 10 / 10000))
            echo "${wan}.${decimal}万"
        else
            echo "$num"
        fi
    else
        echo "0"
    fi
}

format_duration() {
    local seconds="$1"
    if [ -n "$seconds" ] && [ "$seconds" != "null" ] && [ "$seconds" -gt 0 ]; then
        local hours=$((seconds / 3600))
        local minutes=$(( (seconds % 3600) / 60 ))
        local secs=$((seconds % 60))

        if [ $hours -gt 0 ]; then
            printf "%d:%02d:%02d" $hours $minutes $secs
        else
            printf "%d:%02d" $minutes $secs
        fi
    else
        echo "0:00"
    fi
}

seconds_to_hms() {
  local total_seconds="${1:-0}"
  if ! [[ "$total_seconds" =~ ^[0-9]+$ ]]; then echo "0秒"; return; fi
  if [ "$total_seconds" -eq 0 ]; then echo "0秒"; return; fi

  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  local res=""
  ((hours > 0)) && res+="${hours}小时"
  ((minutes > 0)) && res+="${minutes}分钟"
  ((seconds > 0 || (hours==0 && minutes==0))) && res+="${seconds}秒"
  echo "$res"
}



log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \n $1" >> "$LOG_FILE"
}

startup(){
    printf '\033[?25l' #隐藏光标
    term_width=$(tput cols)
    term_height=$(tput lines)
    art_width=42
    art_height=17
    left_padding=$(( (term_width - art_width) / 2 ))
    top_padding=$(( (term_height - art_height) / 2 ))

    padding=$(printf "%*s" "$left_padding")
    vpadding=$(printf "%*s" "$top_padding")

    # 顶部占位
    echo "$vpadding"
    echo -e "${CYAN}"
    cat << "EOF" | sed "s/^/$padding/"
           ██████╗ ██╗██╗     ██╗
           ██╔══██╗██║██║     ██║
           ██████╔╝██║██║     ██║
           ██╔══██╗██║██║     ██║
           ██████╔╝██║███████╗██║
           ╚═════╝ ╚═╝╚══════╝╚═╝

        ████████╗███████╗██████╗ ███╗   ███╗
        ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
           ██║   █████╗  ██████╔╝██╔████╔██║
           ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║
           ██║   ███████╗██║  ██║██║ ╚═╝ ██║
           ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝

            Bilibili Terminal Client
                  Version 0.1.0
EOF
    echo -e "${NC}"
}


curl_bili() {
    local url="$1"
    shift
    local headers=(
        "User-Agent: $USER_AGENT"
        "Referer: https://www.bilibili.com"
        "Origin: https://www.bilibili.com"
        "Accept: application/json, text/plain, */*"
        "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"
        "Connection: keep-alive"
    )

    local curl_cmd=("curl" "-s" "--connect-timeout" "$API_TIMEOUT" "--max-time" "$((API_TIMEOUT * 2))")

    if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
        curl_cmd+=("-b" "$COOKIE_FILE" "-c" "$COOKIE_FILE")
    fi

    for header in "${headers[@]}"; do
        curl_cmd+=("-H" "$header")
    done

    if [ -n "$API_RETRY" ] && [ "$API_RETRY" -gt 0 ]; then
        curl_cmd+=("--retry" "$API_RETRY")
    fi

    if [ -n "$HTTP_PROXY" ]; then
        curl_cmd+=("--proxy" "$HTTP_PROXY")
    fi

    curl_cmd+=("$@" "$url")

    "${curl_cmd[@]}"
}

show_qr() {
    local url="$1"
    if command -v qrencode &> /dev/null; then
        echo ""
        qrencode -t ANSI256UTF8 -s 1 -m 2 "$url"
        echo ""
    else
        echo -e "\n${YELLOW}请访问以下链接扫码登录:${NC}"
        echo "$url"
        echo ""
    fi
}


# ---------------------------------------------------------------------------- #
#                                      API                                     #
# ---------------------------------------------------------------------------- #

# API URL常量
# API_VIDEO_DETAIL="https://api.bilibili.com/x/web-interface/view"
API_UP_DETAIL="https://api.bilibili.com/x/space/acc/info"
API_UP_VIDEOS="https://api.bilibili.com/x/space/arc/search"
API_UP_SEARCH="https://api.bilibili.com/x/web-interface/search/type"
API_RECOMMEND="https://api.bilibili.com/x/web-interface/index/top/feed/rcmd"
API_POPULAR="https://api.bilibili.com/x/web-interface/popular"
API_VIDEO_SEARCH="https://api.bilibili.com/x/web-interface/search/all/v2"
API_HISTORY="https://api.bilibili.com/x/v2/history"
API_WATCHLATER="https://api.bilibili.com/x/v2/history/toview"
API_NAV="https://api.bilibili.com/x/web-interface/nav"
API_LOGIN_QR_GENERATE="https://passport.bilibili.com/x/passport-login/web/qrcode/generate"
API_LOGIN_QR_POLL="https://passport.bilibili.com/x/passport-login/web/qrcode/poll"

# jq解析函数
jqx_video_detail() {
    local res="$1"
    echo "$res" | jq -r '
        .data | "\(.bvid)\t\(.title)\t\(.pic)\t\(.owner.name)\t\(.stat.view)\t\(.stat.like)\t\(.stat.favorite)\t\(.pubdate)"
    ' 2>/dev/null | sed 's/http:/https:/g'
}

jqx_up_detail() {
    local res="$1"
    echo "$res" | jq -r '
        .data | "\(.mid)\t\(.name)\t\(.sign)\t\(.fans)\t\(.level)\t\(.official.title)\t\(.vip.label.text)\t\(.face)"
    ' 2>/dev/null | sed 's/http:/https:/g'
}

jqx_up_videos() {
    local res="$1"
    echo "$res" | jq -r '
        .data.list.vlist[] | "\(.bvid)\t\(.title)\t\(.pic)\t\(.author)\t\(.play)\t\(.comment)\t\(.review)\t\(.created)"
    ' 2>/dev/null | sed 's/http:/https:/g'
}

jqx_up_videos_total() {
    local res="$1"
    echo "$res" | jq -r '.data.page.count // 0'
}

jqx_up_search() {
    local res="$1"
    echo "$res" | jq -r '
        .data.result[] | "\(.mid)\t\(.uname)\t\(.usign // "")\t\(.fans // 0)\t\(.videos // 0)\t\(.upic // "")"
    ' 2>/dev/null | sed 's|//|https://|'
}

jqx_recommend() {
    local res="$1"
    echo "$res" | jq -r '
        if .data.item then .data.item[] | "\(.bvid // "")\t\(.title // "")\t\(.pic // "")\t\(.owner.name // "")\t\(.stat.view // 0)\t\(.stat.like // 0)\t-\t\(.pubdate // 0)"
        elif .data then .data[] | "\(.bvid // "")\t\(.title // "")\t\(.pic // "")\t\(.owner.name // "")\t\(.stat.view // 0)\t\(.stat.like // 0)\t-\t\(.pubdate // 0)"
        else "" end
    ' 2>/dev/null | grep -v "^$" | sed 's/http:/https:/g'
}

jqx_popular() {
    local res="$1"
    echo "$res" | jq -r '
        .data.list[] | "\(.bvid)\t\(.title)\t\(.pic)\t\(.owner.name)\t\(.stat.view)\t\(.stat.like // 0)\t\(.stat.favorite // 0)\t\(.pubdate // 0)"
    ' 2>/dev/null | grep -v "^$" | sed 's/http:/https:/g'
}

jqx_videos() {
    local res="$1"
    echo "$res" | jq -r '
        .data.result[] | select(.result_type=="video") | .data[] | "\(.bvid)\t\(.title)\t\(.pic)\t\(.author)\t\(.play // 0)\t\(.like // 0)\t\(.favorites // 0)\t\(.pubdate // 0)"
    ' 2>/dev/null | \
    sed -e 's/<em class="keyword">//g; s/<\/em>//g' -e 's/\\//g' -e 's/^[ \t]*//;s/[ \t]*$//' | \
    awk -F'\t' 'BEGIN {OFS="\t"} { if ($3 ~ /^\/\//) $3 = "https:" $3; print $0 }' | grep -v "^$"
}

jqx_personal_recommend() {
    local res="$1"
    echo "$res" | jq -r '
        if .data.item then .data.item[] | "\(.bvid // "")\t\(.title // "")\t\(.pic // "")\t\(.owner.name // "")\t\(.stat.view // 0)\t\(.stat.like // 0)\t-\t\(.pubdate // 0)"
        elif .data then .data[] | "\(.bvid // "")\t\(.title // "")\t\(.pic // "")\t\(.owner.name // "")\t\(.stat.view // 0)\t\(.stat.like // 0)\t-\t\(.pubdate // 0)"
        else "" end
    ' 2>/dev/null | grep -v "^$" | sed 's/http:/https:/g'
}

jqx_history() {
    local res="$1"
    echo "$res" | jq -r '
        .data[] | "\(.bvid // "")\t\(.title // "")\t\(.pic // "")\t\(.owner.name // "")\t\(.view_at // 0)\t0\t0\t0"
    ' 2>/dev/null | grep -v "^$" | sed 's/http:/https:/g'
}

jqx_watchlater() {
    local res="$1"
    echo "$res" | jq -r '
        .data.list[] | "\(.bvid // "")\t\(.title // "")\t\(.pic // "")\t\(.owner.name // "")\t0\t0\t0\t0"
    ' 2>/dev/null | grep -v "^$" | sed 's/http:/https:/g'
}

jqerr() {
    local res="$1"
    local code=$(echo "$res" | jq -r '.code // -1')
    local message=$(echo "$res" | jq -r '.message // "未知错误"')
    if [ "$code" != "0" ]; then
        echo "ERROR:$message"
        return 1
    fi
    return 0
}

# --------------------------------- 获取推荐视频列表 --------------------------------- #

fetch_recommend() {
    local page_size="${RECOMMEND_PAGE_SIZE:-20}"
    local res=$(curl_bili "${API_RECOMMEND}?ps=${page_size}")
    echo "$res" | jq empty 2>/dev/null || return 1
    jqx_recommend "$res"
}

# --------------------------------- 获取热门视频列表 --------------------------------- #

fetch_popular() {
    local page_size="${POPULAR_PAGE_SIZE:-20}"
    local res=$(curl_bili "${API_POPULAR}?ps=${page_size}")
    echo "$res" | jq empty 2>/dev/null || return 1
    jqx_popular "$res"
}

# ----------------------------------- 搜索视频 ----------------------------------- #

fetch_videos() {
    local keyword=$(urlencode "$1")
    local page_size="${SEARCH_PAGE_SIZE:-20}"

    local res=$(curl_bili "${API_VIDEO_SEARCH}?keyword=${keyword}&page=1&page_size=${page_size}")
    echo "${res}" > "search.json"
    echo "$res" | jq empty 2>/dev/null || return 1
    jqx_videos "$res"
}

# --------------------------------- 获取个性化推荐列表 -------------------------------- #

fetch_personal_recommend() {
    local page_size="${PERSONAL_PAGE_SIZE:-20}"
    local res=$(curl_bili "${API_RECOMMEND}?ps=${page_size}")
    echo "$res" | jq empty 2>/dev/null || return 1
    jqx_personal_recommend "$res"
}

# --------------------------------- 获取观看历史列表 --------------------------------- #

fetch_history() {
    local res=$(curl_bili "${API_HISTORY}?ps=20")
    echo "$res" | jq empty 2>/dev/null || { echo -e "${RED}获取历史记录失败${NC}"; return 1; }
    jqx_history "$res"
}


# --------------------------------- 获取稍后观看列表 --------------------------------- #
fetch_watchlater() {
    local res=$(curl_bili "${API_WATCHLATER}")
    echo "$res" | jq empty 2>/dev/null || { echo -e "${RED}获取稍后观看失败${NC}"; return 1; }
    jqx_watchlater "$res"
}

# --------------------------------- 添加到稍后观看 --------------------------------- #
add_to_watchlater() {
    local bvid="$1"
    if [ -z "$bvid" ]; then
        echo -e "${RED}缺少视频BV号${NC}"
        return 1
    fi

    if [ ! -f "$COOKIE_FILE" ] || [ ! -s "$COOKIE_FILE" ]; then
        echo -e "${RED}请先登录后再操作${NC}"
        return 1
    fi

    local csrf=$(grep "bili_jct" "$COOKIE_FILE" | awk '{print $7}' | head -1)
    if [ -z "$csrf" ]; then
        csrf=$(grep "bili_jct" "$COOKIE_FILE" | cut -f5 | head -1)
    fi

    local res=$(curl -s -X POST \
        -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -H "User-Agent: $USER_AGENT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "bvid=${bvid}&csrf=${csrf}" \
        "https://api.bilibili.com/x/v2/history/toview/add")
    local code=$(echo "$res" | jq -r '.code // -1')
    if [ "$code" = "0" ]; then
        echo -e "${GREEN}已添加到稍后观看${NC}"
        sleep 2
    else
        local msg=$(echo "$res" | jq -r '.message // "未知错误"')
        echo -e "${RED}添加失败: $msg${NC}"
    fi
}

# ================= 预览处理函数 =================
preview_video() {
    local line="$1"
    local pic_url=$(echo "$line" | cut -d$'\t' -f3)
    local title=$(echo "$line" | cut -d$'\t' -f2)
    local author=$(echo "$line" | cut -d$'\t' -f4)
    local views=$(echo "$line" | cut -d$'\t' -f5)
    local likes=$(echo "$line" | cut -d$'\t' -f6)
    local favorites=$(echo "$line" | cut -d$'\t' -f7)
    local pubdate=$(echo "$line" | cut -d$'\t' -f8)
    local bvid=$(echo "$line" | cut -d$'\t' -f1)

    echo -e "${YELLOW}标题:${NC} $title"
    echo -e "${BLUE}UP主:${NC} $author"
    echo -e "${GREEN}播放:${NC} $(format_number "$views")"
    echo -e "${RED}点赞:${NC} $(format_number "$likes")"
    echo -e "${PURPLE}收藏:${NC} $([ "$favorites" = "-" ] && echo "-" || format_number "$favorites")"
    echo -e "${CYAN}发布日期:${NC} $(timestamp_to_date "$pubdate")"

    echo ""

    if [ "$ENABLE_PREVIEW" = "true" ] && [ -n "$pic_url" ] && [ "$pic_url" != "null" ]; then
        curl -s -H "User-Agent: $USER_AGENT" "$pic_url" 2>/dev/null | \
        chafa -s "${FZF_PREVIEW_COLUMNS:-80}x${FZF_PREVIEW_LINES:-20}" -
    else
        echo "无封面"
    fi
}

preview_up() {
    local line="$1"
    local mid=$(echo "$line" | cut -d$'\t' -f1)
    local uname=$(echo "$line" | cut -d$'\t' -f2)
    local usign=$(echo "$line" | cut -d$'\t' -f3)
    local fans=$(echo "$line" | cut -d$'\t' -f4)
    local videos=$(echo "$line" | cut -d$'\t' -f5)
    local upic=$(echo "$line" | cut -d$'\t' -f6)

    echo -e "${YELLOW}UP主:${NC} $uname"
    echo -e "${BLUE}MID:${NC} $mid"
    echo -e "${GREEN}粉丝:${NC} $(format_number "$fans")"
    echo -e "${RED}视频数:${NC} $(format_number "$videos")"

    if [ -n "$usign" ] && [ "$usign" != "null" ] && [ "$usign" != "" ]; then
        echo -e "${CYAN}签名:${NC} $usign"
    fi

    echo ""

    if [ "$ENABLE_PREVIEW" = "true" ] && [ -n "$upic" ] && [ "$upic" != "null" ]; then
        curl -s -H "User-Agent: $USER_AGENT" "$upic" 2>/dev/null | \
        chafa  -s "${FZF_PREVIEW_COLUMNS:-60}x${FZF_PREVIEW_LINES:-15}" -
    else
        echo "无头像"
    fi
}

# 通用的预览处理函数
preview_handler() {
    local line="$1"
    local preview_type="$2"


    case "$preview_type" in
        "video") preview_video "$line" ;;
        "up") preview_up "$line" ;;
        *) echo "未知预览类型" ;;
    esac
}

# ================= 登录相关函数 =================
check_login() {
    local res
    res=$(curl_bili "${API_NAV}" 2>/dev/null)

    if ! echo "$res" | jq empty 2>/dev/null; then
        echo -e "${YELLOW}未登录 (API响应异常)${NC}"
        return 1
    fi

    local is_login
    is_login=$(echo "$res" | jq -r '.data.isLogin' 2>/dev/null)

    if [ "$is_login" = "true" ]; then
        local uname
        uname=$(echo "$res" | jq -r '.data.uname' 2>/dev/null)
        echo -e "${GREEN}已登录: $uname${NC}"
        return 0
    else
        echo -e "${YELLOW}未登录 ${NC}"
        return 1
    fi
}



do_login() {
    if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
        local res=$(curl_bili "${API_NAV}" 2>/dev/null)
        if echo "$res" | jq empty 2>/dev/null; then
            local is_login=$(echo "$res" | jq -r '.data.isLogin' 2>/dev/null)
            if [ "$is_login" = "true" ]; then
                echo -e "${GREEN}已登录，无需重复登录${NC}"
                return 0
            fi
        fi
    fi

    > "$COOKIE_FILE"
    echo "正在获取登录二维码..."

    local qr_res
    qr_res=$(curl -s -c "$COOKIE_FILE" \
        -H "User-Agent: $USER_AGENT" \
        -H "Referer: https://www.bilibili.com" \
        "${API_LOGIN_QR_GENERATE}")

    if ! echo "$qr_res" | jq empty 2>/dev/null; then
        echo -e "${RED}错误: API返回无效响应${NC}"
        return 1
    fi

    local code=$(echo "$qr_res" | jq -r '.code')
    if [ "$code" != "0" ]; then
        echo -e "${RED}错误: 获取二维码失败 (code: $code)${NC}"
        return 1
    fi

    local qr_url=$(echo "$qr_res" | jq -r '.data.url')
    local qr_key=$(echo "$qr_res" | jq -r '.data.qrcode_key')

    if [ -z "$qr_url" ] || [ "$qr_url" = "null" ] || [ -z "$qr_key" ]; then
        echo -e "${RED}错误: 无法获取二维码信息${NC}"
        return 1
    fi

    echo -e "${GREEN}获取二维码成功${NC}"
    show_qr "$qr_url"
    echo -e "${YELLOW}请使用 Bilibili 手机端扫码登录${NC}"
    echo -e "${BLUE}提示: 扫码后需要在手机上确认登录${NC}"
    echo ""

    echo -n "等待扫码"
    local poll_count=0
    local max_poll=60

    while [ $poll_count -lt $max_poll ]; do
        sleep 3
        poll_count=$((poll_count + 1))

        local poll_res
        poll_res=$(curl -s -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
            -H "User-Agent: $USER_AGENT" \
            -H "Referer: https://www.bilibili.com" \
            "${API_LOGIN_QR_POLL}?qrcode_key=$qr_key")

        if ! echo "$poll_res" | jq empty 2>/dev/null; then
            echo -n "!"
            continue
        fi

        local poll_code=$(echo "$poll_res" | jq -r '.code')
        local data_code=$(echo "$poll_res" | jq -r '.data.code // 86101')

        if [ "$poll_code" != "0" ]; then
            echo -n "?"
            continue
        fi

        case $data_code in
            0)
                echo -e "\n${GREEN}登录成功！${NC}"
                echo -e "${GREEN}Cookie 已保存至 $COOKIE_FILE${NC}"
                if check_login; then return 0; else echo -e "${YELLOW}登录状态未确认${NC}"; return 1; fi
            ;;
            86038) echo -e "\n${RED}二维码已失效${NC}"; return 1 ;;
            86090) [ $poll_count -eq 2 ] && echo -e "\n${GREEN}已扫码，请确认${NC}"; echo -n "✓" ;;
            86101) echo -n "." ;;
            *) echo -n "?" ;;
        esac
    done
    echo -e "\n${YELLOW}扫码超时${NC}"
    return 1
}

# ================= FZF 界面函数 =================

run_fzf_video_list() {
    local mode="$1"
    local query="$2"

    local raw_cmd
    local prompt

    case $mode in
        rec)        raw_cmd="fetch_recommend"; prompt="推荐视频" ;;
        popular)    raw_cmd="fetch_popular"; prompt="热门视频" ;;
        search)     raw_cmd="fetch_videos \"$query\""; prompt="搜索: $query" ;;
        personal)   raw_cmd="fetch_personal_recommend"; prompt="为你推荐" ;;
        history)    raw_cmd="fetch_history"; prompt="历史记录" ;;
        watchlater) raw_cmd="fetch_watchlater"; prompt="稍后观看" ;;
        up_videos)  raw_cmd="fetch_up_videos \"$query\""; prompt="UP主视频" ;;
        *) return 1 ;;
    esac

    # 构造缓存键
    local cache_key="${mode}_$(echo -n "$query" | md5sum | cut -d' ' -f1)"
    local cache_file="$CACHE_DIR/$cache_key"

    # 获取数据的命令
    local fetch_cmd="bash \"$0\" --fetch-cached \"$cache_key\" $raw_cmd"

    # 快捷键设置
    local key_play="${KEY_PLAY:-enter}"
    local key_play_all="${KEY_PLAY_ALL:-alt-enter}"
    local key_download="${KEY_DOWNLOAD:-ctrl-d}"
    local key_refresh="${KEY_REFRESH:-ctrl-r}"
    local key_watchlater="${KEY_WATCHLATER:-ctrl-w}"

    local out

    # 如果缓存文件存在，直接从缓存加载
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
        out=$(cat "$cache_file")
    else
        out=$(eval "$fetch_cmd" 2>/dev/null)
    fi

    while true; do
        if [ -z "$out" ]; then
            echo -e "${RED}获取数据失败，请检查网络连接${NC}"
            read -p "按回车键继续..."
            return 1
        fi

        # 过滤掉空行和无效行
        local filtered_out=$(echo "$out" | awk -F'\t' '{if ($1 != "" && $2 != "") print $0}')

        # 运行fzf
        local fzf_out
        fzf_out=$(echo "$filtered_out" | \
            fzf --ansi --style full \
            --color="$FZF_COLOR" \
            --delimiter=$'\t' \
            --with-nth=2 \
            --border \
            --prompt="❯ " \
            --header="BiliTerm - $prompt" \
            --layout=reverse \
            --preview "bash \"$0\" --preview video {}" \
            --preview-window="right:${PREVIEW_WIDTH:-50%}:wrap" \
            --expect="$key_play_all" \
            --bind '?:change-preview-window:hidden|right' \
            --bind "$key_refresh:execute-silent(rm -f \"$cache_file\")+reload(eval $fetch_cmd)" \
            --bind "$key_download:execute(echo -e '${YELLOW}正在下载...${NC}'; yt-dlp --cookies \"$COOKIE_FILE\" -o \"$DOWNLOAD_DIR/%(title)s.%(ext)s\" 'https://www.bilibili.com/video/{1}'; read -p '按回车键继续...')" \
            --bind "$key_watchlater:execute(echo -e '${YELLOW}正在添加到稍后观看...${NC}'; bash \"$0\" --add-watchlater {1}; read -p '按回车键继续...')" \
            --bind "$key_play:accept" 2>/dev/null)

        # 处理 FZF 退出情况
        if [ -z "$fzf_out" ]; then break; fi

        # 解析输出
        local key=$(echo "$fzf_out" | head -n1)
        local selected=$(echo "$fzf_out" | tail -n +2)

        if [ "$key" = "$key_play_all" ]; then
            # 播放列表模式
            if [ -s "$cache_file" ]; then
                echo -e "${GREEN}正在准备播放列表...${NC}"
                local playlist_file="$CACHE_DIR/playlist.m3u"
                > "$playlist_file"

                awk -F'\t' '{print "https://www.bilibili.com/video/" $1}' "$cache_file" > "$playlist_file"

                local count=$(wc -l < "$playlist_file")
                echo -e "${CYAN}已加载 $count 个视频到播放列表${NC}"

                # 使用配置的播放器播放
                if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
                    $VIDEO_PLAYER $PLAYER_ARGS --playlist="$playlist_file" --ytdl-raw-options="cookies=$COOKIE_FILE"
                else
                    $VIDEO_PLAYER $PLAYER_ARGS --playlist="$playlist_file"
                fi
            else
                echo -e "${RED}列表为空${NC}"
                sleep 1
            fi
            continue
        fi

        # 单个播放模式
        if [ -n "$selected" ]; then
            local bvid=$(echo "$selected" | cut -d$'\t' -f1)
            echo -e "${GREEN}正在启动 $VIDEO_PLAYER 播放: $bvid ${NC}"
            if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
                $VIDEO_PLAYER $PLAYER_ARGS --ytdl-raw-options="cookies=$COOKIE_FILE" "https://www.bilibili.com/video/$bvid" 2>/dev/null
            else
                $VIDEO_PLAYER $PLAYER_ARGS "https://www.bilibili.com/video/$bvid" 2>/dev/null
            fi
        else
            break
        fi
    done
}

run_fzf_up_search() {
    local keyword="$1"

    # 搜索UP主
    echo -e "${YELLOW}正在搜索UP主: $keyword${NC}"

    local cache_key="up_search_$(echo -n "$keyword" | md5sum | cut -d' ' -f1)"
    local cache_file="$CACHE_DIR/$cache_key"
    local fetch_cmd="fetch_up_search \"$keyword\""
    local full_cmd="bash \"$0\" --fetch-cached \"$cache_key\" $fetch_cmd"

    while true; do
        local out
        out=$(eval "$full_cmd" 2>/dev/null)

        if echo "$out" | grep -q "^ERROR:"; then
            local error_msg=$(echo "$out" | sed 's/^ERROR://')
            echo -e "${RED}搜索失败: $error_msg${NC}"
            read -p "按回车键继续..."
            return 1
        fi

        if [ -z "$out" ]; then
            echo -e "${YELLOW}未找到相关UP主${NC}"
            read -p "按回车键继续..."
            return 1
        fi

        # 运行fzf选择UP主
        local fzf_out
        fzf_out=$(echo "$out" | \
            fzf --ansi --style full \
            --color="$FZF_COLOR" \
            --delimiter=$'\t' \
            --with-nth=2 \
            --border \
            --prompt="❯ " \
            --header="BiliTerm - UP主搜索" \
            --layout=reverse \
            --preview "bash \"$0\" --preview up {}" \
            --preview-window="right:${PREVIEW_WIDTH:-40%}:wrap" \
            --bind '?:change-preview-window:hidden|bottom|hidden|right' \
            --bind "ctrl-r:execute-silent(rm -f \"$cache_file\")+reload($full_cmd)" \
            --bind "enter:accept" 2>/dev/null)

        if [ -z "$fzf_out" ]; then break; fi

        # 获取选中的UP主MID
        local mid=$(echo "$fzf_out" | cut -d$'\t' -f1)
        local uname=$(echo "$fzf_out" | cut -d$'\t' -f2)
        local videos=$(echo "$fzf_out" | cut -d$'\t' -f5)

        if [ -n "$mid" ]; then
            # 如果没有视频，不作反应
            if [ "$videos" = "0" ] || [ -z "$videos" ]; then
                continue
            fi
            # 进入UP主视频列表
            run_fzf_video_list "up_videos" "$mid"
        fi
    done
}

# ================= 菜单界面 =================
get_login_info() {
    if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
        local res=$(curl_bili "${API_NAV}" 2>/dev/null)
        if echo "$res" | jq empty 2>/dev/null; then
            local is_login=$(echo "$res" | jq -r '.data.isLogin' 2>/dev/null)
            if [ "$is_login" = "true" ]; then
                local uname=$(echo "$res" | jq -r '.data.uname' 2>/dev/null)
                echo "✓ 已登录: $uname"
                return 0
            fi
        fi
    fi
    echo "⚠ 未登录 "
    return 1
}

show_menu() {
    local login_info=$(get_login_info)

    local menu_options=(
        "  个人推荐"
        "  推荐视频"
        "  热门视频"
        "  搜索视频"
        "  搜索UP主"
        "  历史记录"
        "  稍后观看"
        "  配置管理"
        "  扫码登录"
        "  关于帮助"
        "  退出程序"
    )

    local choice
    choice=$(printf '%s\n' "${menu_options[@]}" | \
        fzf --ansi --style full \
        --color="$FZF_COLOR" \
        --border \
        --no-input \
        --prompt="❯ " \
        --pointer='▓' \
        --header="BiliTerm  $login_info" \
        --height=100% \
        --layout=reverse \
        --preview="echo -e '\n${CYAN}快捷键说明${NC}\n\n${YELLOW}主页:${NC}\n• [Enter] 选择功能\n• [Ctrl+R] 刷新状态\n \n${YELLOW}视频列表页:${NC}\n• [${KEY_PLAY:-enter}] 播放单个视频\n• [${KEY_PLAY_ALL:-alt-enter}] 播放当前列表\n• [${KEY_DOWNLOAD:-ctrl-d}] 下载视频\n• [${KEY_WATCHLATER:-ctrl+w}] 添加到稍后观看\n• [${KEY_REFRESH:-ctrl-r}] 刷新列表\n• [Esc] 返回上级\n\n${GREEN}预览窗口显示:${NC}\n• 视频标题/UP主/播放量\n• 点赞/收藏/发布日期\n• 弹幕/投币/视频时长'" \
        --preview-window="right:50%:wrap" \
        --bind '?:change-preview-window:hidden|bottom|hidden|right' \
        --bind "ctrl-r:reload(echo '正在刷新登录状态...'; login_info=\$(get_login_info); printf '%s\n' \"\${menu_options[@]}\")" \
        )

    echo "$choice"
}

search_video() {
    echo -e "${YELLOW}请输入搜索关键词:${NC}"
    read -e keyword
    if [ -n "$keyword" ]; then
        run_fzf_video_list "search" "$keyword"
    fi
}

search_up() {
    echo -e "${YELLOW}请输入UP主名称:${NC}"
    read -e keyword
    if [ -n "$keyword" ]; then
        run_fzf_up_search "$keyword"
    fi
}

show_settings() {
    local settings_options=(
        " 打开配置目录"
        " 编辑配置文件"
        " 重置配置文件"
        " 清除缓存文件"
        " 查看系统信息"
        " ⬅ 返回主菜单"
    )

        while true; do
        local choice
        choice=$(printf '%s\n' "${settings_options[@]}" | \
            fzf --ansi --style full \
            --color="$FZF_COLOR" \
            --border \
            --prompt="设置 > " \
            --header="配置管理" \
            --height=100% \
            --layout=reverse \
            --preview="echo -e '\n${CYAN}当前配置信息${NC}\n\n${YELLOW}配置目录:${NC} $CONFIG_DIR\n${GREEN}缓存目录:${NC} $CACHE_BASE_DIR\n${PURPLE}下载目录:${NC} $DOWNLOAD_DIR\n${RED}用户代理:${NC} $USER_AGENT'" \
            --preview-window="down:wrap:40%" 2>/dev/null)

        case "$choice" in
            *打开配置目录*)
                echo -e "${GREEN}打开配置目录: $CONFIG_DIR${NC}"
                if command -v xdg-open &> /dev/null; then
                    xdg-open "$CONFIG_DIR" 2>/dev/null
                elif command -v open &> /dev/null; then
                    open "$CONFIG_DIR" 2>/dev/null
                else
                    echo -e "目录位置: $CONFIG_DIR"
                fi
                read -p "按回车键继续..."
                ;;
            *编辑配置文件*)
                echo -e "${GREEN}编辑配置文件: $CONFIG_FILE${NC}"
                ${EDITOR:-vi} "$CONFIG_FILE"
                echo -e "${YELLOW}配置已更新，重启后生效${NC}"
                read -p "按回车键继续..."
                ;;
            *重置配置文件*)
                echo -e "${RED}确认重置配置文件？(y/N):${NC}"
                read -n 1 confirm
                echo
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -f "$CONFIG_FILE"
                    load_config
                    echo -e "${GREEN}配置文件已重置${NC}"
                fi
                read -p "按回车键继续..."
                ;;
            *清除缓存文件*)
                echo -e "${YELLOW}确认清除所有缓存？(y/N):${NC}"
                read -n 1 confirm
                echo
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -rf "$CACHE_BASE_DIR"/*
                    echo -e "${GREEN}缓存已清除${NC}"
                fi
                read -p "按回车键继续..."
                ;;
            *查看系统信息*)
                echo -e "\n${CYAN}系统信息:${NC}"
                echo -e "${YELLOW}脚本版本:${NC} 0.1.0"
                echo -e "${GREEN}配置目录:${NC} $CONFIG_DIR"
                echo -e "${BLUE}缓存目录:${NC} $CACHE_BASE_DIR"
                echo -e "${RED}Cookie文件:${NC} $COOKIE_FILE"
                echo -e "\n${CYAN}依赖检查:${NC}"
                for cmd in curl jq fzf chafa mpv yt-dlp; do
                    if command -v "$cmd" &> /dev/null; then
                        echo -e "${GREEN}✓${NC} $cmd: $(which $cmd)"
                    else
                        echo -e "${RED}✗${NC} $cmd: 未找到"
                    fi
                done
                echo ""
                read -p "按回车键继续..."
                ;;
            *返回主菜单*|"") break ;;
            *) echo "无效选择"; sleep 1 ;;
        esac
    done
}

show_about() {
    clear
    echo -e "${CYAN}"
cat <<EOF
╔══════════════════════════════════════════╗
║           Bili-Term v2.0.0               ║
║      终端中的 Bilibili 客户端            ║
╚══════════════════════════════════════════╝
EOF
    echo "${NC}"
    echo ""
    echo -e "${YELLOW}功能特性:${NC}"
    echo -e "  ${GREEN}✓${NC} 视频推荐/热门/搜索"
    echo -e "  ${GREEN}✓${NC} UP主搜索与视频浏览"
    echo -e "  ${GREEN}✓${NC} 个人推荐/历史记录/稍后看"
    echo -e "  ${GREEN}✓${NC} 扫码登录（支持大会员）"
    echo -e "  ${GREEN}✓${NC} 视频播放与下载"
    echo -e "  ${GREEN}✓${NC} 封面预览与详细信息"
    echo -e "  ${GREEN}✓${NC} XDG 配置规范支持"
    echo ""
    echo -e "${YELLOW}快捷键:${NC}"
    echo -e "  ${CYAN}Enter${NC}    播放选中视频"
    echo -e "  ${CYAN}Alt+Enter${NC} 播放当前列表"
    echo -e "  ${CYAN}Ctrl+D${NC}    下载视频"
    echo -e "  ${CYAN}Ctrl+R${NC}    刷新列表"
    echo -e "  ${CYAN}Esc${NC}       返回上级"
    echo ""
    echo -e "${YELLOW}配置目录:${NC} $CONFIG_DIR"
    echo -e "${YELLOW}缓存目录:${NC} $CACHE_BASE_DIR"
    echo ""
    echo -e "${BLUE}GitHub:${NC} https://github.com/akirco/bili-term"
    echo -e "${BLUE}反馈:${NC} https://github.com/akirco/bili-term/issues"
    echo ""
    read -p "按回车键返回主菜单..."
}

run_main_loop() {
    while true; do
        clear

        local choice=$(show_menu)
        if [ -z "$choice" ]; then
            exit 0
        fi

        case "$choice" in
            *推荐视频*) run_fzf_video_list "rec" ;;
            *热门视频*) run_fzf_video_list "popular" ;;
            *搜索视频*) search_video ;;
            *搜索UP主*) search_up ;;
            *个人推荐*)
                if check_login; then
                    run_fzf_video_list "personal"
                else
                    echo -e "${RED}需要登录才能查看个人推荐${NC}"
                    sleep 1
                fi
                ;;
            *历史记录*)
                if check_login; then
                    run_fzf_video_list "history"
                else
                    echo -e "${RED}需要登录才能查看历史记录${NC}"
                    sleep 1
                fi
                ;;
            *稍后观看*)
                if check_login; then
                    run_fzf_video_list "watchlater"
                else
                    echo -e "${RED}需要登录才能查看稍后观看${NC}"
                    sleep 1
                fi
                ;;
            *配置管理*) show_settings ;;
            *扫码登录*)
                if check_login; then
                    echo -e "${RED}已登录...${NC}"
                    read -p "按回车键继续..."
                else
                    do_login; read -p "按回车键继续..."
                fi
             ;;
            *关于帮助*) show_about ;;
            *退出程序*)
                exit 0
                ;;
            *) echo "无效选择"; sleep 1 ;;
        esac
    done
}

# ================= CLI 模式处理 =================
if [ "$1" = "--fetch-cached" ]; then
    mode="$2"
    shift 2
    cache_file="$CACHE_DIR/$mode"

    # 如果缓存不存在或为空，执行命令并写入缓存
    if [ ! -s "$cache_file" ]; then
        "$@" > "$cache_file" 2>/dev/null
    fi

    # 输出缓存内容
    cat "$cache_file" 2>/dev/null
    exit 0
fi

if [ "$1" = "--preview" ]; then
    preview_type="$2"
    shift 2
    preview_handler "$*" "$preview_type"
    exit 0
fi

if [ "$1" = "--add-watchlater" ]; then
    bvid="$2"
    add_to_watchlater "$bvid"
    exit 0
fi

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo -e "${CYAN}Bili-Term 使用说明${NC}"
    echo ""
    echo "使用方法:"
    echo "  $0                    # 启动交互式界面"
    echo "  $0 --help             # 显示帮助信息"
    echo "  $0 --version          # 显示版本信息"
    echo "  $0 --config           # 显示配置信息"
    echo ""
    echo "配置目录: $CONFIG_DIR"
    echo "缓存目录: $CACHE_BASE_DIR"
    echo ""
    exit 0
fi

if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
    echo "Bili-Term v0.1.0"
    exit 0
fi

if [ "$1" = "--config" ]; then
    echo -e "${CYAN}配置信息:${NC}"
    echo "配置文件: $CONFIG_FILE"
    echo "Cookie文件: $COOKIE_FILE"
    echo "下载目录: $DOWNLOAD_DIR"
    echo "用户代理: $USER_AGENT"
    echo "播放器: $VIDEO_PLAYER"
    exit 0
fi

# ================= 主程序入口 =================
clear

check_dependency

startup

sleep 1

run_main_loop