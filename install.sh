#!/usr/bin/env bash

set -e

SCRIPT_NAME="bili-term"
BIN_URL="https://raw.githubusercontent.com/akirco/bili-term/refs/heads/main/bili.sh"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bili-term"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bili-term"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== $SCRIPT_NAME 安装脚本 ===${NC}"
echo ""

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1"
        return 1
    fi
}

echo -e "${YELLOW}检查依赖...${NC}"
echo ""
deps_ok=true
check_command curl || deps_ok=false
check_command jq || deps_ok=false
check_command fzf || deps_ok=false
check_command chafa || deps_ok=false
check_command mpv || deps_ok=false
check_command yt-dlp || deps_ok=false

if [ "$deps_ok" = false ]; then
    echo ""
    echo -e "${YELLOW}缺少依赖，是否安装？(需要 sudo 权限)${NC}"
    read -p "[Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo -e "${YELLOW}正在安装依赖...${NC}"
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y curl jq ffmpeg imagemagick
            elif command -v pacman &> /dev/null; then
            sudo pacman -S curl jq fzf ffmpeg imagemagick
            elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl jq fzf ffmpeg ImageMagick
            elif command -v brew &> /dev/null; then
            brew install curl jq fzf ffmpeg imagemagick chafa mpv yt-dlp
        else
            echo -e "${RED}无法自动安装，请手动安装以下依赖:${NC}"
            echo "  curl, jq, fzf, chafa, mpv, yt-dlp"
            exit 1
        fi
        
        if command -v yt-dlp &> /dev/null; then
            echo -e "${GREEN}yt-dlp 已安装${NC}"
        else
            echo -e "${YELLOW}正在安装 yt-dlp...${NC}"
            sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
            sudo chmod a+rx /usr/local/bin/yt-dlp
        fi
        
        if command -v chafa &> /dev/null; then
            echo -e "${GREEN}chafa 已安装${NC}"
        else
            echo -e "${YELLOW}正在安装 chafa...${NC}"
            sudo curl -L https://github.com/hpjansson/chafa/releases/latest/download/chafa -o /usr/local/bin/chafa 2>/dev/null || \
            sudo apt-get install -y chafa 2>/dev/null || \
            echo -e "${RED}chafa 安装失败，请手动安装${NC}"
            sudo chmod a+rx /usr/local/bin/chafa 2>/dev/null || true
        fi
    else
        echo -e "${RED}安装取消${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}创建目录...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CACHE_DIR"
mkdir -p "$INSTALL_DIR"
echo -e "  ${GREEN}✓${NC} 配置目录: $CONFIG_DIR"
echo -e "  ${GREEN}✓${NC} 缓存目录: $CACHE_DIR"

echo ""
echo -e "${YELLOW}正在安装脚本...${NC}"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/bili.sh"
if [ -f "$SCRIPT_PATH" ]; then
    cp "$SCRIPT_PATH" "$INSTALL_DIR/bili"
    chmod +x "$INSTALL_DIR/bili"
    echo -e "  ${GREEN}✓${NC} 已安装到 $INSTALL_DIR/bili"
else
    curl -sL "$BIN_URL" -o "$INSTALL_DIR/bili"
    chmod +x "$INSTALL_DIR/bili"
    echo -e "  ${GREEN}✓${NC} 已从 GitHub 安装到 $INSTALL_DIR/bili"
fi

echo ""
if [ -f "$CONFIG_DIR/config.conf" ]; then
    echo -e "${GREEN}配置文件已存在，跳过创建${NC}"
else
    cat > "$CONFIG_DIR/config.conf" << 'EOF'
# Bili-Term 配置文件
# 按需修改以下配置项

# 播放器设置
VIDEO_PLAYER="mpv"
PLAYER_ARGS=""

# API 超时时间（秒）
API_TIMEOUT=10
API_RETRY=3

# 缓存设置
CACHE_DURATION=3600

# 分页大小
RECOMMEND_PAGE_SIZE=20
POPULAR_PAGE_SIZE=20
SEARCH_PAGE_SIZE=20
PERSONAL_PAGE_SIZE=20

# 预览设置
ENABLE_PREVIEW="true"
SHOW_STATISTICS="false"
PREVIEW_WIDTH=50

# 快捷键
KEY_PLAY="enter"
KEY_PLAY_ALL="alt-enter"
KEY_DOWNLOAD="ctrl-d"
KEY_REFRESH="ctrl-r"
KEY_WATCHLATER="ctrl-w"
EOF
    echo -e "  ${GREEN}✓${NC} 配置文件: $CONFIG_DIR/config.conf"
fi

echo ""
echo -e "${GREEN}=== 安装完成 ===${NC}"
echo ""
echo -e "${YELLOW}使用方法:${NC}"
echo "  $INSTALL_DIR/bili"
echo ""
echo -e "${YELLOW}快捷键:${NC}"
echo "  Enter       播放选中视频"
echo "  Alt+Enter   播放当前列表"
echo "  Ctrl+D      下载视频"
echo "  Ctrl+W      添加到稍后观看"
echo "  Ctrl+R      刷新列表"
echo "  Esc         返回上级"
echo ""
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}建议将以下路径添加到 PATH:${NC}"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
    echo -e "${YELLOW}可以添加到 ~/.bashrc 或 ~/.zshrc:${NC}"
    echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc"
fi
