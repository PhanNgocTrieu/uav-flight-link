#!/usr/bin/env bash
# UAV Flight-Link System — Environment setup script
# Chạy 1 lần trên máy mới (WSL2/Linux). Idempotent — chạy lại nhiều lần không lỗi.

set -e

echo "==> Cập nhật apt..."
sudo apt update

echo "==> Cài build tools cơ bản..."
sudo apt install -y build-essential cmake git pkg-config

echo "==> Cài can-utils..."
sudo apt install -y can-utils

echo "==> Setup vcan0 (bỏ qua nếu đã tồn tại)..."
if ! ip link show vcan0 &>/dev/null; then
    sudo ip link add dev vcan0 type vcan
    sudo ip link set up vcan0
    echo "    vcan0 đã được tạo."
else
    echo "    vcan0 đã tồn tại, bỏ qua."
fi

echo "==> Cài rt-tests (cyclictest cho đo jitter)..."
sudo apt install -y rt-tests

echo "==> Cài QEMU + ARM toolchain (cho Phase 3, option B)..."
sudo apt install -y qemu-system-arm gcc-arm-none-eabi

echo "==> Cài clang-tidy + cppcheck (static analysis)..."
sudo apt install -y clang-tidy cppcheck

echo "==> Cài OpenSSL dev headers (cho Phase 6)..."
sudo apt install -y libssl-dev

echo ""
echo "=== Kiểm tra nhanh ==="
echo "-- vcan0 status:"
ip link show vcan0

echo ""
echo "-- Test CAN loopback (gửi/nhận thử):"
candump vcan0 -n 1 &
sleep 0.5
cansend vcan0 123#DEADBEEF
sleep 1

echo ""
echo "Setup hoàn tất. Nếu không có lỗi ở trên, môi trường đã sẵn sàng cho toàn bộ project."
