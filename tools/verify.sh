#!/usr/bin/env bash
# 一条命令跑完「构建 + 10 组本地回归」。
#
# 用法：
#   tools/verify.sh              # 构建 + 全部回归
#   tools/verify.sh --skip-build # 只跑回归（改文档/脚本时用）
#   tools/verify.sh --tests-only # 只构建测试包（entry@ohosTest）
#
# 设备侧（Hypium / 真机）不在这里：本机没有设备，设备项一律按「未测」记录。
# 工具链默认取命令行的 HarmonyOS CLT；可用 HMOS_CLT_HOME 覆盖。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLT="${HMOS_CLT_HOME:-/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$CLT/sdk}"
export PATH="$CLT/hvigor/bin:$CLT/node/bin:$CLT/ohpm/bin:$PATH"

cd "$ROOT" || exit 1

MODE="${1:-}"

if [ "$MODE" != "--skip-build" ] && [ "$MODE" != "--tests-only" ]; then
  echo "== 构建主包 =="
  if ! hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon \
      > /tmp/weaver-build.log 2>&1; then
    echo "BUILD FAILED（日志：/tmp/weaver-build.log）"
    grep -E "ArkTS:ERROR" /tmp/weaver-build.log | head -20
    exit 1
  fi
  warns=$(grep -c 'ArkTS:WARN' /tmp/weaver-build.log)
  echo "BUILD SUCCESSFUL  errors=$(grep -c 'ArkTS:ERROR' /tmp/weaver-build.log)  warnings=$warns"
  # 增量构建会跳过 CompileArkTS，此时 warnings=0 不代表代码没告警
  if [ "$warns" -eq 0 ] && grep -q "up-to-date" /tmp/weaver-build.log; then
    echo "  注：本次为增量构建（未重新编译），告警数需用 hvigorw clean 后重跑才准确"
  fi
fi

if [ "$MODE" = "--tests-only" ]; then
  echo "== 构建测试包 =="
  if ! hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon \
      > /tmp/weaver-testbuild.log 2>&1; then
    echo "TEST BUILD FAILED（日志：/tmp/weaver-testbuild.log）"
    exit 1
  fi
  echo "TEST BUILD SUCCESSFUL"
  exit 0
fi

echo "== 本地回归 =="
total=0
failed=0
for f in tools/*.cjs; do
  out="$(node "$f" 2>&1)"
  code=$?
  if [ $code -ne 0 ]; then
    echo "FAIL  $f"
    echo "$out" | tail -20
    failed=$((failed + 1))
    continue
  fi
  n="$(printf '%s\n' "$out" | sed -n 's/.*: \([0-9][0-9]*\) checks passed.*/\1/p' | tail -1)"
  if [ -z "$n" ]; then n=0; fi
  total=$((total + n))
  printf 'PASS  %-34s %s\n' "$f" "$n"
done

echo "----------------------------------------"
echo "回归合计：$total 项，失败脚本：$failed 个"
if [ $failed -ne 0 ]; then
  exit 1
fi

echo "提醒：设备侧（中文输入法 / 安装卸载 / 外接屏 / 帧率）未包含在内，需按 docs/design/canvas-e2e-checklist.md 与 docs/refactor/multidevice-self-test.md 在真机执行。"
