#!/bin/bash
# 测试脚本：检查当前 Claude Code session 状态
echo "=== Claude Code Sessions ==="
SESSION_DIR="$HOME/.claude/sessions"

if [ ! -d "$SESSION_DIR" ]; then
  echo "目录不存在: $SESSION_DIR"
  exit 1
fi

files=$(ls "$SESSION_DIR"/*.json 2>/dev/null)
if [ -z "$files" ]; then
  echo "没有 session 文件"
  exit 0
fi

count=0
interactive=0
for f in $files; do
  count=$((count+1))
  pid=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('pid','?'))" 2>/dev/null)
  status=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('status','?'))" 2>/dev/null)
  kind=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('kind','?'))" 2>/dev/null)
  sessionId=$(python3 -c "import json,sys; d=json.load(open('$f')); print(d.get('sessionId','?')[:8])" 2>/dev/null)

  # 检查进程是否存活
  if kill -0 "$pid" 2>/dev/null; then
    alive="✓ 存活"
    # 检查进程命令行
    cmdline=$(ps -p "$pid" -o command= 2>/dev/null | head -c 100)
    if echo "$cmdline" | grep -qi "claude"; then
      detected="✓ claude检测通过"
    else
      detected="✗ claude检测失败 (cmd: $cmdline)"
    fi
  else
    alive="✗ 已死亡"
    detected="-"
  fi

  if [ "$kind" = "interactive" ]; then
    interactive=$((interactive+1))
  fi

  echo "[$sessionId] pid=$pid status=$status kind=$kind | $alive | $detected"
done

echo ""
echo "总计: $count 个 session，其中 interactive: $interactive 个"
