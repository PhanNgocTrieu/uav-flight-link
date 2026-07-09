# UAV Flight-Link System — Learning & Interview-Prep Project

> Project mô phỏng một hệ thống điều khiển drone + datalink, chạy hoàn toàn trên Linux (không cần phần cứng thật), dùng để vừa học vừa ôn kiến thức Senior C++/Embedded/UAV.

## Mục tiêu

Xây dựng một hệ thống đủ lớn để phủ được các mảng kiến thức:
- Modern C++ (11 → 20): RAII, move semantics, templates, CRTP, custom allocator
- HAL / driver layering theo tinh thần AUTOSAR (BSW / RTE / Application)
- RTOS & real-time Linux: scheduling, jitter, watchdog, fault detection
- Giao thức: CAN, SPI/UART (mock), MAVLink
- IPC hiệu năng cao: shared memory, lock-free ring buffer, zero-copy
- Bảo mật: mã hóa datalink, secure boot giả lập, ký/verify firmware
- Kiến trúc & tài liệu hoá theo tinh thần ASPICE

Định hướng phỏng vấn:
| Vòng phỏng vấn | Giai đoạn nên nhấn mạnh |
|---|---|
| Automotive C++ (Senior Embedded) | Giai đoạn 2 (CAN/SPI/LIN), 3 (RTOS), 6 (secure boot), 9 (tài liệu ASPICE) |
| UAV/Datalink (Software Engineer) | Giai đoạn 4 (MAVLink), 5 (zero-copy IPC), 6 (mã hóa datalink), 7 (video pipeline) |

## Kiến trúc tổng thể

```
┌─────────────────────┐      IPC (shared memory)      ┌─────────────────────┐
│  Flight Controller   │ ─────────────────────────────▶│  Datalink Gateway   │
│  Core (C++)          │◀───────────────────────────── │  (C++)              │
│  - control loop       │                                │  - MAVLink encode   │
│  - sensor fusion mock │                                │  - encryption       │
│  - watchdog/fault     │                                │  - lossy link (tc)  │
└─────────────────────┘                                └──────────┬──────────┘
                                                                    │ UDP/TCP (netem)
                                                                    ▼
                                                        ┌─────────────────────┐
                                                        │  Ground Station     │
                                                        │  (Python/Qt/Web)    │
                                                        │  - telemetry view   │
                                                        │  - command send     │
                                                        └─────────────────────┘
```

## Môi trường mô phỏng (không cần phần cứng)

| Cần giả lập | Công cụ Linux | Ghi chú |
|---|---|---|
| CAN bus | `vcan` (virtual CAN) + `can-utils` | Code driver giống hệt CAN thật, chỉ khác device |
| SPI/UART | Interface trừu tượng (`ISpiBus`, `IUartBus`) + `MockBus` implementation | `HardwareBus` để trống, note "implement khi có board" |
| MCU/firmware thật | QEMU (`qemu-system-arm`, board `lm3s6965evb`/`netduinoplus2`) chạy FreeRTOS/Zephyr | Firmware thật, RTOS thật, không cần board vật lý |
| Real-time Linux | `SCHED_FIFO` + `cyclictest` (gói `rt-tests`) | Không bắt buộc patch kernel PREEMPT_RT, vẫn đo được số liệu tương đối |
| RF/datalink lossy | `tc netem` (loss, delay, jitter) trên veth/network namespace | Test retransmission logic dưới điều kiện mất gói thực tế |
| Nhiều node/ECU | Docker Compose, mỗi container = 1 "ECU"/node | Dễ demo kiến trúc phân tán |

### Setup nhanh (chạy 1 lần)

```bash
# CAN ảo
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
sudo apt install can-utils

# Real-time testing tools
sudo apt install rt-tests

# QEMU cho ARM
sudo apt install qemu-system-arm gcc-arm-none-eabi

# Network emulation (thường có sẵn)
sudo apt install iproute2
```

## Lộ trình theo giai đoạn

### Giai đoạn 0 — Nền tảng & khung project (tuần 1)
- [ ] CMake multi-module, cấu trúc thư mục theo layer (Application / RTE / BSW / HAL)
- [ ] CI cơ bản: build + GoogleTest + clang-tidy/cppcheck
- **Ôn lại:** build system, static analysis, coding standard (tinh thần MISRA C++)

### Giai đoạn 1 — Modern C++ Core (tuần 1-2)
- [ ] Framework "Component" dùng template + CRTP (Sensor, Actuator, Task)
- [ ] RAII, smart pointers, move semantics, `std::variant`/`std::optional` cho state machine
- [ ] Custom allocator đơn giản (tránh heap alloc trong control loop)
- **Ôn lại:** C++11→20 features, memory model, move semantics, template metaprogramming

### Giai đoạn 2 — Hardware Abstraction Layer (tuần 2-3)
- [ ] CAN qua `vcan0` + SocketCAN API (`PF_CAN`, `SOCK_RAW`, `CAN_RAW`)
- [ ] Interface `ISpiBus`/`IUartBus` + `MockBus` implementation
- **Ôn lại:** SPI/UART/CAN protocol, HAL design pattern, driver layering

### Giai đoạn 3 — Real-time & RTOS (tuần 3-4)
- [ ] Option A: Linux `SCHED_FIFO`/`sched_setattr`, đo latency bằng `cyclictest`
- [ ] Option B (nâng cao): FreeRTOS trên QEMU ARM Cortex-M ảo (build bằng `arm-none-eabi-gcc`, chạy `qemu-system-arm -M lm3s6965evb -kernel firmware.elf`)
- [ ] Watchdog task + fault detection (safety monitor kiểu AUTOSAR)
- **Ôn lại:** RTOS scheduling, priority inversion, real-time Linux, watchdog design

### Giai đoạn 4 — Giao thức & Datalink (tuần 4-6)
- [ ] Implement MAVLink cho telemetry + command
- [ ] Layer CAN riêng cho phần "automotive" (ECU giả lập gửi dữ liệu qua CAN)
- [ ] Framing, CRC, retransmission cho datalink lossy (test với `tc netem`)
- **Ôn lại:** MAVLink, CAN/LIN/FlexRay, checksum/CRC, protocol design

### Giai đoạn 5 — IPC & Zero-copy (tuần 6-7)
- [ ] Shared memory (`mmap`) + ring buffer lock-free giữa Flight Controller và Gateway
- [ ] So sánh hiệu năng với pipe/socket thường
- **Ôn lại:** IPC mechanisms, lock-free ring buffer, zero-copy techniques

### Giai đoạn 6 — Bảo mật (tuần 7-8)
- [ ] Mã hóa datalink bằng mbedTLS/OpenSSL (DTLS)
- [ ] Secure boot giả lập: ký firmware bằng OpenSSL, verify chữ ký trước khi "load" (exec/QEMU)
- [ ] (Tùy chọn) Module verify signature viết bằng Rust, gọi qua FFI từ C++
- **Ôn lại:** secure boot, cryptography cơ bản, FFI/interop

### Giai đoạn 7 — Video/Telemetry pipeline (tuần 8-9, tùy chọn)
- [ ] GStreamer pipeline nén/giải nén video giả lập, đo băng thông
- **Ôn lại:** video compression pipeline, bandwidth-constrained streaming

### Giai đoạn 8 — Ground Station & tích hợp (tuần 9-10)
- [ ] Ground station Python (PyQt hoặc web dashboard): telemetry real-time + gửi lệnh
- **Ôn lại:** system integration, end-to-end testing

### Giai đoạn 9 — Hoàn thiện theo chuẩn senior (tuần 10-12)
- [ ] Architecture doc theo tinh thần ASPICE: yêu cầu → thiết kế → test case
- [ ] Test suite đầy đủ: unit + integration + fault injection (mất tín hiệu, sensor lỗi)
- [ ] Code review checklist, đo coverage

## Ghi chú triển khai thực tế

- Không cần làm hết tất cả giai đoạn trước khi phỏng vấn — ưu tiên dựng khung + hoàn chỉnh 2-3 giai đoạn liên quan trực tiếp JD, phần còn lại note rõ trong README như "kế hoạch mở rộng".
- Giai đoạn 3 (RTOS/QEMU) và giai đoạn 6 (secure boot) tốn thời gian setup toolchain hơn dự kiến nếu chưa quen build firmware bare-metal — cộng thêm ~3-4 ngày dự phòng.
- Tên kỹ thuật (protocol, chuẩn, tool) giữ nguyên tiếng Anh kể cả trong tài liệu tiếng Việt.

## Cách dùng file này để prompt Claude sau này

Khi quay lại làm tiếp, có thể copy nguyên phần "Giai đoạn X" đang làm dở vào prompt, kèm câu hỏi cụ thể, ví dụ:

```
Tôi đang làm Giai đoạn 2 (HAL) trong project UAV Flight-Link System (xem README đính kèm).
Tôi cần viết interface ISpiBus + MockBus implementation bằng C++20.
Hãy giúp tôi thiết kế interface này.
```

Hoặc đơn giản upload file README.md này kèm câu: "Đây là project tôi đang làm theo lộ trình này, tôi đang ở Giai đoạn ... , hãy giúp tôi ..."
