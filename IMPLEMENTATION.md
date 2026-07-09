# UAV Flight-Link System — Sơ đồ kiến trúc & Phân kỳ Implementation

> File này trực quan hóa kiến trúc hệ thống và cho thấy hệ thống "lớn dần" qua từng phase như thế nào. Dùng kèm với `PROJECT_PLAN.md` (chi tiết task) và `README.md` (tổng quan).

## 1. Sơ đồ kiến trúc tổng thể (mục tiêu cuối cùng)

```mermaid
flowchart TB
    subgraph FC["Flight Controller Core (C++)"]
        SM["State Machine<br/>(Idle/Armed/Flying/Fault)"]
        CL["Control Loop<br/>SCHED_FIFO"]
        WD["Watchdog Task"]
        SENSOR["Sensor Fusion (mock)"]
    end

    subgraph HAL["HAL Layer"]
        CAN["ICanBus → SocketCAN (vcan0)"]
        SPI["ISpiBus → MockSpiBus"]
        UART["IUartBus → MockUartBus"]
    end

    subgraph IPC["IPC Layer"]
        RING["Lock-free Ring Buffer<br/>(shared memory)"]
    end

    subgraph GW["Datalink Gateway (C++)"]
        MAV["MAVLink Encoder/Decoder"]
        SEC["DTLS Encryption"]
        RETRY["Retransmission Logic<br/>(seq + ACK)"]
    end

    subgraph NET["Lossy Network (tc netem)"]
        LINK["UDP Link<br/>loss/delay simulation"]
    end

    subgraph GS["Ground Station (Python/Web)"]
        UI["Dashboard UI"]
        WS["WebSocket Server"]
    end

    subgraph BOOT["Secure Boot (offline)"]
        SIGN["Firmware Signing (OpenSSL)"]
        VERIFY["Bootloader Verify<br/>(C++ / Rust FFI)"]
    end

    ECU["ECU giả lập<br/>(CAN sender)"] -->|CAN frame| CAN
    CAN --> FC
    SPI --> FC
    UART --> FC
    FC <-->|zero-copy| RING
    RING <--> GW
    GW <-->|encrypted, lossy| LINK
    LINK <--> GS
    SIGN -.->|ký firmware| VERIFY
    VERIFY -.->|verify trước khi chạy| FC

    style FC fill:#2b6cb0,color:#fff
    style GW fill:#2f855a,color:#fff
    style GS fill:#b7791f,color:#fff
    style HAL fill:#4a5568,color:#fff
    style BOOT fill:#742a2a,color:#fff
```

## 2. Kiến trúc theo tầng (layer view — tinh thần AUTOSAR)

```mermaid
flowchart TB
    APP["Application Layer<br/>Flight logic, State machine"]
    RTE["RTE (Runtime Environment)<br/>Component framework (CRTP), IPC routing"]
    BSW["Basic Software (BSW)<br/>Protocol stack: MAVLink, CAN framing, Security"]
    HAL2["HAL<br/>ICanBus / ISpiBus / IUartBus"]
    DRV["Driver / OS<br/>SocketCAN, Linux scheduler, QEMU/FreeRTOS"]

    APP --> RTE --> BSW --> HAL2 --> DRV

    style APP fill:#2b6cb0,color:#fff
    style RTE fill:#2c5282,color:#fff
    style BSW fill:#2f855a,color:#fff
    style HAL2 fill:#4a5568,color:#fff
    style DRV fill:#1a202c,color:#fff
```

---

## 3. Hệ thống lớn dần qua từng Phase

### Phase 0 — Khung project
```mermaid
flowchart LR
    CMAKE["CMake multi-module"] --> TEST["GoogleTest sanity check"]
    TEST --> CI["GitHub Actions CI"]
```
**Có gì chạy được:** build sạch, 1 test giả, CI xanh. Chưa có logic thật.

### Phase 1 — Modern C++ Core
```mermaid
flowchart TB
    subgraph FC1["Flight Controller (skeleton)"]
        SM1["State Machine (variant)"]
        TASK["TaskBase<Derived> — CRTP"]
        ALLOC["PoolAllocator"]
    end
```
**Có gì chạy được:** State machine transition test, benchmark CRTP vs virtual, xác nhận zero heap alloc.

### Phase 2 — HAL
```mermaid
flowchart LR
    ECU2["ECU giả lập"] -->|CAN frame| VCAN["vcan0"]
    VCAN --> ICAN["ICanBus (SocketCAN)"]
    ICAN --> FC2["Flight Controller"]
    MOCKSPI["MockSpiBus"] -.-> FC2
    MOCKUART["MockUartBus"] -.-> FC2
```
**Có gì chạy được:** CAN frame thật đi qua vcan0, Flight Controller parse được. SPI/UART là mock nhưng interface đã đúng chuẩn để swap sau này.

### Phase 3 — RTOS / Real-time
```mermaid
flowchart TB
    CL3["Control Loop<br/>SCHED_FIFO priority 80"] --> MEASURE["cyclictest / jitter log"]
    CL3 --> WD3["Watchdog Task"]
    WD3 -->|timeout| FAULT["State: Fault"]
    QEMU["QEMU + FreeRTOS<br/>(option B)"] -.->|song song, không phụ thuộc| CL3
```
**Có gì chạy được:** số liệu jitter thật SCHED_FIFO vs SCHED_OTHER, watchdog chuyển state khi control loop treo. QEMU/FreeRTOS là nhánh phụ, độc lập.

### Phase 4 — Giao thức & Datalink
```mermaid
flowchart LR
    FC4["Flight Controller"] --> GW4["Datalink Gateway"]
    GW4 -->|encode| MAVMSG["MAVLink message"]
    MAVMSG -->|UDP| NETEM["tc netem<br/>loss 5-30%, delay"]
    NETEM --> GSMOCK["Ground Station<br/>(pymavlink script tạm)"]
    GW4 -->|retry nếu mất ACK| MAVMSG
    ECU4["ECU giả lập"] -->|CAN| GWCAN["CAN-to-MAVLink Gateway"]
    GWCAN --> NETEM
```
**Có gì chạy được:** MAVLink thật trên wire (thấy được bằng Wireshark), retransmission hoạt động dưới điều kiện mất gói, có thêm nhánh CAN-to-MAVLink minh họa gateway pattern.

### Phase 5 — Zero-copy IPC
```mermaid
flowchart LR
    FC5["Flight Controller"] <-->|"mmap + atomic<br/>ring buffer"| GW5["Datalink Gateway"]
    BENCH["Benchmark:<br/>ring buffer vs socket vs pipe"]
```
**Có gì chạy được:** đường truyền nội bộ FC↔Gateway chuyển từ socket sang ring buffer, có số liệu benchmark latency/throughput thật.

### Phase 6 — Bảo mật
```mermaid
flowchart TB
    GW6["Gateway"] -->|"DTLS"| NETEM6["Lossy network"]
    NETEM6 --> GS6["Ground Station"]
    SIGN6["OpenSSL: ký firmware.bin"] --> BOOTLOADER["Bootloader (C++)"]
    RUSTFFI["Rust: verify signature<br/>(qua FFI, tùy chọn)"] -.-> BOOTLOADER
    BOOTLOADER -->|verify OK| RUN["Cho phép chạy firmware"]
    BOOTLOADER -->|verify FAIL| REJECT["Từ chối, log lỗi"]
```
**Có gì chạy được:** traffic bắt bằng Wireshark không đọc được plaintext, bootloader từ chối firmware bị sửa đổi.

### Phase 7 — Video pipeline (tùy chọn)
```mermaid
flowchart LR
    SRC["Video test source"] --> ENC["H.264 encode"] --> UDP7["UDP"] --> NETEM7["tc netem<br/>giới hạn băng thông"] --> DEC["Decode"] --> DISPLAY["Hiển thị"]
```
**Có gì chạy được:** video chạy qua đường truyền băng thông hạn chế, đo được bitrate/latency/frame drop.

### Phase 8 — Ground Station thật
```mermaid
flowchart TB
    GW8["Gateway"] <-->|MAVLink over DTLS| WS8["WebSocket Server"]
    WS8 <--> UI8["Dashboard UI<br/>(telemetry chart + command button)"]
```
**Có gì chạy được:** demo end-to-end live — mở dashboard thấy telemetry cập nhật real-time, gửi lệnh thấy phản hồi.

### Phase 9 — Hoàn thiện
```mermaid
flowchart LR
    ALL["Toàn bộ hệ thống"] --> FAULTINJ["Fault injection tests"]
    ALL --> COVERAGE["Code coverage report"]
    ALL --> DOCS["architecture.md + requirements.md"]
```
**Có gì chạy được:** hệ thống đầy đủ, có test fault injection, coverage report, tài liệu kiến trúc hoàn chỉnh.

---

## 4. Bảng map: Component ↔ Phase ra đời ↔ Kiến thức ôn lại

| Component | Ra đời ở Phase | Kiến thức chính |
|---|---|---|
| CMake + CI | 0 | Build system, static analysis |
| StateMachine, TaskBase (CRTP), PoolAllocator | 1 | Modern C++, memory model |
| ICanBus/ISpiBus/IUartBus + Mock/SocketCAN | 2 | HAL pattern, CAN protocol |
| SCHED_FIFO control loop, Watchdog | 3 | RTOS, real-time scheduling |
| FreeRTOS on QEMU (tùy chọn) | 3 | Bare-metal RTOS thật |
| MAVLink encode/decode, retransmission | 4 | Protocol design, datalink |
| CAN-to-MAVLink Gateway | 4 | Gateway pattern (automotive ↔ UAV) |
| Ring buffer (mmap + atomic) | 5 | IPC, lock-free, zero-copy |
| DTLS encryption | 6 | Datalink security |
| Bootloader + firmware signing | 6 | Secure boot |
| Rust FFI verify module (tùy chọn) | 6 | Đa ngôn ngữ, memory-safe interop |
| GStreamer pipeline (tùy chọn) | 7 | Video compression, bandwidth |
| Dashboard UI + WebSocket | 8 | System integration |
| Fault injection, coverage, docs | 9 | ASPICE-style rigor |

---

## 5. Cách dùng file này

- Khi bắt đầu một Phase mới, mở lại đúng sơ đồ Phase đó để nhớ component nào cần nối với component nào.
- Khi trình bày trong phỏng vấn, có thể vẽ tay lại sơ đồ Phase 9 (đầy đủ) từ trí nhớ — nếu vẽ được nghĩa là đã hiểu hệ thống đủ sâu.
- Sơ đồ này render trực tiếp trên GitHub (Mermaid được hỗ trợ native trong `.md`), không cần công cụ ngoài.
