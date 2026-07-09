# UAV Flight-Link System — Kế hoạch thực thi (Execution Plan)

> Đây không phải tài liệu tham khảo — đây là kế hoạch làm việc thực tế. Mỗi giai đoạn có: mục tiêu cụ thể, task theo thứ tự, lệnh cần chạy, deliverable để tự kiểm tra "đã xong chưa", và điểm dừng an toàn nếu hết thời gian.

## Nguyên tắc làm việc

1. **Làm theo thứ tự, không nhảy cóc** — mỗi giai đoạn phụ thuộc vào cấu trúc của giai đoạn trước.
2. **Mỗi giai đoạn kết thúc bằng 1 commit hoạt động được** — không để dở dang qua giai đoạn sau.
3. **Time-box:** nếu một task vượt quá 150% thời gian dự kiến, dừng lại, ghi chú "known limitation" trong README, và đi tiếp — không sa lầy.
4. **Ưu tiên phỏng vấn:** nếu deadline gấp, chỉ cần hoàn thành đến hết Giai đoạn 4 (đã đủ để nói chuyện tự tin ở cả 2 vòng phỏng vấn) — Giai đoạn 5-9 là điểm cộng, không phải bắt buộc.

## Tổng quan timeline (12 tuần, ~10-12h/tuần)

| Tuần | Giai đoạn | Trọng tâm |
|---|---|---|
| 1 | 0 | Khung project, CI |
| 1-2 | 1 | Modern C++ core |
| 2-3 | 2 | HAL (CAN/SPI/UART mock) |
| 3-4 | 3 | RTOS/real-time |
| 4-6 | 4 | MAVLink + datalink lossy |
| 6-7 | 5 | Zero-copy IPC |
| 7-8 | 6 | Bảo mật (mã hóa + secure boot) |
| 8-9 | 7 | Video pipeline (tùy chọn) |
| 9-10 | 8 | Ground station |
| 10-12 | 9 | Tài liệu hoá + test hoàn chỉnh |

---

## GIAI ĐOẠN 0 — Khung project & CI (Tuần 1, ~6-8h)

**Mục tiêu:** Có một project build được, chạy được 1 unit test, CI xanh trên GitHub.

### Task theo thứ tự

1. Tạo repo, cấu trúc thư mục:
```
uav-flight-link/
├── CMakeLists.txt
├── apps/
│   ├── flight_controller/
│   ├── datalink_gateway/
│   └── ground_station/        # Python, làm ở giai đoạn 8
├── libs/
│   ├── hal/                   # Giai đoạn 2
│   ├── rtos_util/              # Giai đoạn 3
│   ├── protocol/               # Giai đoạn 4
│   ├── ipc/                    # Giai đoạn 5
│   └── security/                # Giai đoạn 6
├── tests/
├── docs/
│   └── architecture.md         # Giai đoạn 9
├── scripts/
│   └── setup_env.sh
└── README.md
```
2. Viết `CMakeLists.txt` gốc dùng `add_subdirectory` cho từng lib, C++20, bật `-Wall -Wextra -Werror`.
3. Cài GoogleTest qua `FetchContent`, viết 1 test giả (`TEST(Sanity, AlwaysTrue)`) để xác nhận pipeline chạy.
4. Viết `scripts/setup_env.sh` gồm toàn bộ lệnh cài đặt môi trường (vcan, rt-tests, qemu, gcc-arm-none-eabi) — chạy 1 lần, dùng lại suốt project.
5. Thêm `.clang-tidy` với rule set cơ bản (modernize-*, cppcoreguidelines-*).
6. GitHub Actions workflow: build + ctest + clang-tidy trên mỗi push.

### Deliverable để tự kiểm tra
- [ ] `cmake -B build && cmake --build build` chạy sạch, không warning
- [ ] `ctest --test-dir build` pass
- [ ] Push lên GitHub, Action chạy xanh
- [ ] `scripts/setup_env.sh` chạy được trên máy sạch (thử trong container/VM mới nếu có thể)

---

## GIAI ĐOẠN 1 — Modern C++ Core (Tuần 1-2, ~10-12h)

**Mục tiêu:** Có framework `Component` tái sử dụng được cho mọi module sau này (Sensor, Actuator, Task).

### Task theo thứ tự

1. Thiết kế interface `IComponent` (pure virtual: `init()`, `update(dt)`, `shutdown()`).
2. Viết `TaskBase<Derived>` dùng CRTP để tránh virtual call overhead trong control loop — so sánh benchmark CRTP vs virtual bằng Google Benchmark.
3. Viết `StateMachine` dùng `std::variant` + `std::visit` cho trạng thái bay (Idle/Armed/Flying/Landing/Fault).
4. Viết `PoolAllocator` cố định kích thước (fixed-size block allocator) — mục tiêu: zero heap allocation trong control loop sau khi khởi tạo.
5. Viết test đo: chạy control loop giả 10,000 vòng, assert không có `malloc` nào xảy ra (dùng `LD_PRELOAD` hook đơn giản hoặc Valgrind Massif để xác nhận).
6. Áp dụng move semantics + `unique_ptr` xuyên suốt ownership của Component.

### Deliverable để tự kiểm tra
- [ ] Unit test cho `StateMachine`: cover mọi transition hợp lệ + reject transition không hợp lệ
- [ ] Benchmark CRTP vs virtual có số liệu thật (ghi vào `docs/benchmarks.md`)
- [ ] Chứng minh được (bằng test hoặc log) control loop không gọi heap allocation sau init
- [ ] Có thể giải thích bằng miệng: tại sao chọn CRTP ở đây, đánh đổi gì

---

## GIAI ĐOẠN 2 — Hardware Abstraction Layer (Tuần 2-3, ~10-12h)

**Mục tiêu:** CAN chạy thật qua vcan, có driver layer trừu tượng cho SPI/UART dù chỉ mock.

### Task theo thứ tự

1. Setup `vcan0`, test bằng tay trước với `cansend`/`candump` để chắc chắn môi trường đúng.
2. Viết `ICanBus` interface (`send(CanFrame)`, `receive() -> optional<CanFrame>`), implement bằng SocketCAN raw socket (`PF_CAN`, `SOCK_RAW`, `CAN_RAW`).
3. Viết một "ECU giả lập" (process riêng) gửi CAN frame định kỳ (giống cảm biến tốc độ động cơ) — dùng để test integration.
4. Thiết kế `ISpiBus`/`IUartBus`, implement `MockSpiBus`/`MockUartBus` dùng in-memory queue.
5. Viết `HardwareSpiBus`/`HardwareUartBus` — chỉ định nghĩa signature + `throw std::logic_error("not implemented — requires hardware")`, kèm comment giải thích sẽ implement khi có board thật.
6. Viết integration test: Flight Controller đọc CAN frame qua `ICanBus`, parse thành giá trị RPM giả.

### Deliverable để tự kiểm tra
- [ ] `candump vcan0` thấy được frame do ECU giả lập gửi
- [ ] Integration test đọc CAN frame → parse → log giá trị đúng
- [ ] Có thể vẽ sơ đồ layer (Application → HAL interface → Mock/Hardware implementation) và giải thích tại sao tách lớp này quan trọng khi lên chip thật

---

## GIAI ĐOẠN 3 — Real-time & RTOS (Tuần 3-4, ~12-15h)

**Mục tiêu:** Đo được số liệu real-time thật (không chỉ nói suông), và/hoặc chạy được FreeRTOS thật trên QEMU.

### Task theo thứ tự (Option A — bắt buộc)

1. Chạy control loop process với `sched_setattr(SCHED_FIFO, priority=80)`.
2. Cài `rt-tests`, chạy `cyclictest -p 80 -i 1000 -l 10000` để lấy baseline jitter của hệ thống.
3. Đo jitter của chính control loop process bằng cách log timestamp mỗi vòng lặp, tính max/avg deviation so với chu kỳ mong muốn (vd 10ms).
4. So sánh: `SCHED_OTHER` (default) vs `SCHED_FIFO` — ghi số liệu vào `docs/benchmarks.md`.
5. Viết watchdog task riêng: nếu control loop không "kick" watchdog trong X ms, watchdog chuyển state machine sang `Fault`.

### Task theo thứ tự (Option B — nâng cao, nếu còn thời gian tuần 4)

6. Cài `arm-none-eabi-gcc`, tải FreeRTOS kernel source.
7. Build một firmware tối thiểu chạy 2 task FreeRTOS (blink giả lập bằng log qua UART ảo) trên `qemu-system-arm -M lm3s6965evb`.
8. Nếu chạy được, viết thêm 1 task giả lập gửi CAN-like message qua UART để liên kết ý tưởng với phần Linux ở trên.

### Deliverable để tự kiểm tra
- [ ] Có bảng số liệu jitter SCHED_OTHER vs SCHED_FIFO thật (không phải số tưởng tượng)
- [ ] Watchdog test: cố tình treo control loop, xác nhận state chuyển sang Fault đúng thời gian
- [ ] (Nếu làm Option B) Log output từ QEMU cho thấy FreeRTOS task chạy đúng
- [ ] Có thể giải thích priority inversion là gì và cách tránh (dù project này chưa chắc demo được, nhưng phải giải thích được bằng lời)

**Điểm dừng an toàn:** Nếu Option B tốn quá 2 buổi mà chưa build được firmware, dừng lại — Option A đã đủ để trả lời phỏng vấn về RTOS.

---

## GIAI ĐOẠN 4 — Giao thức & Datalink (Tuần 4-6, ~15-18h)

**Mục tiêu:** Có luồng MAVLink thật gửi/nhận qua mạng lossy, retransmission logic hoạt động và test được dưới điều kiện mất gói.

### Task theo thứ tự

1. Cài thư viện MAVLink (submodule hoặc generate từ XML định nghĩa message chuẩn, vd HEARTBEAT, ATTITUDE, GLOBAL_POSITION_INT).
2. Datalink Gateway: encode telemetry giả (từ Flight Controller) thành MAVLink message, gửi qua UDP.
3. Ground station tạm thời = 1 script Python nhỏ dùng `pymavlink` để nhận và in ra (sẽ nâng cấp thành app đầy đủ ở Giai đoạn 8).
4. Setup network namespace + veth pair, áp `tc netem loss 5% delay 100ms 20ms distribution normal` giữa Gateway và Ground station.
5. Viết retransmission logic: sequence number + ACK cho message quan trọng (command), chấp nhận mất gói cho telemetry tần suất cao.
6. Viết test: cố tình tăng loss lên 30%, xác nhận command vẫn tới đích (có retry), telemetry có thể mất nhưng hệ thống không crash.
7. Thêm CAN layer riêng (tách biệt với MAVLink) để có ví dụ automotive: ECU giả lập gửi qua CAN, một module "gateway" đọc CAN → convert sang MAVLink-like format → gửi qua network (minh họa gateway pattern giữa 2 loại bus, rất hay gặp trong xe/drone thật).

### Deliverable để tự kiểm tra
- [ ] `candump`/`tcpdump`/Wireshark thấy được MAVLink packet thật trên wire
- [ ] Test với `tc netem loss 30%`: command vẫn đến đích, có log retry
- [ ] Có bảng so sánh: message nào cần ACK (command) vs message nào chấp nhận best-effort (telemetry), và giải thích tại sao
- [ ] CAN-to-MAVLink gateway module chạy được end-to-end

---

## GIAI ĐOẠN 5 — IPC & Zero-copy (Tuần 6-7, ~8-10h)

**Mục tiêu:** Có số liệu benchmark thật so sánh shared memory ring buffer vs socket/pipe.

### Task theo thứ tự

1. Viết lock-free SPSC (single-producer single-consumer) ring buffer trên `mmap` shared memory giữa Flight Controller và Gateway.
2. Dùng `std::atomic` cho head/tail index, chú ý memory ordering (`memory_order_acquire`/`release`).
3. Viết benchmark: throughput + latency của ring buffer vs Unix domain socket vs named pipe, cùng một khối lượng dữ liệu telemetry giả (vd 1000 msg/s, mỗi msg 200 bytes).
4. Thay thế đường truyền cũ (nếu ở Giai đoạn 4 dùng socket nội bộ) bằng ring buffer mới, xác nhận hệ thống vẫn hoạt động đúng.

### Deliverable để tự kiểm tra
- [ ] Bảng benchmark thật: latency p50/p99 và throughput của 3 phương pháp
- [ ] Có thể giải thích rõ tại sao cần `atomic` + memory ordering ở đây, race condition nào có thể xảy ra nếu làm sai
- [ ] Test chạy song song nhiều lần (stress test) không có data corruption

---

## GIAI ĐOẠN 6 — Bảo mật (Tuần 7-8, ~10-12h)

**Mục tiêu:** Datalink được mã hóa thật, có cơ chế verify firmware trước khi "boot".

### Task theo thứ tự

1. Tích hợp mbedTLS hoặc OpenSSL: bọc kênh UDP giữa Gateway và Ground station bằng DTLS.
2. Viết test: bắt gói bằng Wireshark/tcpdump, xác nhận payload không đọc được ở dạng plaintext (trước khi có TLS thì đọc được, sau khi có TLS thì không — chụp lại 2 ảnh làm bằng chứng).
3. Secure boot giả lập: viết script ký file `.bin` bằng private key (OpenSSL), viết chương trình C++ "bootloader" verify chữ ký bằng public key trước khi cho phép "load" (exec hoặc nạp vào QEMU).
4. Test: sửa 1 byte trong file firmware sau khi ký, xác nhận bootloader từ chối load.
5. (Tùy chọn, điểm cộng lớn) Viết module verify signature bằng Rust (dùng crate `ring` hoặc `ed25519-dalek`), expose qua `extern "C"` FFI, gọi từ C++ bootloader — minh họa khả năng tích hợp ngôn ngữ memory-safe cho phần bảo mật quan trọng.

### Deliverable để tự kiểm tra
- [ ] Ảnh chụp Wireshark: trước/sau khi có DTLS
- [ ] Test firmware bị sửa 1 byte → bootloader từ chối, log rõ lý do
- [ ] (Nếu làm FFI) Build thành công cả Rust static lib + C++ linking, chạy đúng
- [ ] Có thể giải thích chain-of-trust của secure boot: ai ký, ai giữ private key, verify ở đâu

---

## GIAI ĐOẠN 7 — Video/Telemetry pipeline (Tuần 8-9, tùy chọn, ~6-8h)

**Mục tiêu:** Hiểu và demo được 1 pipeline nén/truyền video cơ bản dưới ràng buộc băng thông.

### Task theo thứ tự

1. Dùng GStreamer, tạo pipeline: video test source → encode (H.264) → gửi qua UDP → decode ở phía nhận.
2. Áp `tc netem` giới hạn băng thông (vd 500kbps) lên link, quan sát ảnh hưởng đến chất lượng/độ trễ video.
3. Ghi lại số liệu: bitrate, frame drop, latency ở các mức băng thông khác nhau.

### Deliverable để tự kiểm tra
- [ ] Pipeline chạy được end-to-end, video hiển thị ở phía nhận
- [ ] Bảng số liệu bitrate vs chất lượng/latency

**Ghi chú:** Giai đoạn này có thể bỏ qua nếu deadline phỏng vấn gấp — không phải core requirement của cả 2 JD.

---

## GIAI ĐOẠN 8 — Ground Station & tích hợp (Tuần 9-10, ~10-12h)

**Mục tiêu:** Có 1 giao diện thật (không phải script) hiển thị telemetry real-time và gửi lệnh.

### Task theo thứ tự

1. Chọn: PyQt (desktop) hoặc Flask/FastAPI + WebSocket (web dashboard) — nên chọn web nếu muốn demo dễ dàng qua trình duyệt khi phỏng vấn.
2. Nhận MAVLink message qua `pymavlink`, forward qua WebSocket tới frontend.
3. Frontend đơn giản: hiển thị attitude, position, battery giả lập dạng biểu đồ real-time.
4. Thêm nút gửi command (arm/disarm, thay đổi mode) → gửi ngược lại qua Gateway.
5. Test toàn bộ end-to-end: Flight Controller → Gateway (mã hóa, lossy) → Ground Station, cả 2 chiều.

### Deliverable để tự kiểm tra
- [ ] Demo chạy được live: mở dashboard, thấy số liệu telemetry cập nhật real-time
- [ ] Gửi lệnh từ dashboard, thấy state machine ở Flight Controller phản hồi đúng
- [ ] Quay video demo ngắn (2-3 phút) — rất hữu ích để show trong phỏng vấn nếu được hỏi

---

## GIAI ĐOẠN 9 — Hoàn thiện theo chuẩn senior (Tuần 10-12, ~12-15h)

**Mục tiêu:** Project trông và hoạt động như một sản phẩm được kỹ sư senior thiết kế, không phải một bài tập.

### Task theo thứ tự

1. Viết `docs/architecture.md`: sơ đồ kiến trúc, quyết định thiết kế quan trọng + lý do (tại sao CRTP, tại sao ring buffer, tại sao tách HAL...).
2. Viết `docs/requirements.md` theo tinh thần ASPICE tối giản: liệt kê requirement (vd "Hệ thống phải phát hiện mất tín hiệu trong vòng 500ms") → map sang test case tương ứng.
3. Fault injection test suite: mô phỏng mất CAN, mất datalink, sensor trả giá trị vô lý (NaN, out-of-range) → xác nhận hệ thống chuyển Fault state đúng, không crash.
4. Đo code coverage (`gcov`/`lcov`), đặt mục tiêu tối thiểu cho core logic (vd 80% cho `libs/`).
5. Viết code review checklist riêng (dựa trên kinh nghiệm rút ra từ project), đặt trong `docs/code_review_checklist.md`.
6. Dọn README.md chính: tổng quan, cách build, cách chạy demo, sơ đồ kiến trúc, liên kết tới các doc khác.

### Deliverable để tự kiểm tra
- [ ] `docs/architecture.md` và `docs/requirements.md` hoàn chỉnh, có thể đưa cho người khác đọc hiểu được
- [ ] Fault injection test pass đầy đủ
- [ ] Coverage report xuất ra được, có số liệu cụ thể
- [ ] README chính đủ để một người lạ clone repo và chạy demo trong < 10 phút

---

## Checklist tổng để tự đánh giá trước phỏng vấn

- [ ] Build sạch từ đầu trên máy mới (`scripts/setup_env.sh` + `cmake --build`)
- [ ] Có ít nhất 1 demo chạy được live (không chỉ code, phải chạy được)
- [ ] Có số liệu benchmark thật ở ít nhất 2 chỗ (RTOS jitter, IPC throughput)
- [ ] Có thể vẽ tay sơ đồ kiến trúc tổng thể trong 2 phút mà không cần nhìn tài liệu
- [ ] Có thể giải thích rõ 3 quyết định kỹ thuật khó nhất và đánh đổi của chúng
- [ ] README + docs đủ rõ để dùng làm "bằng chứng" gửi kèm CV/portfolio

## Cách dùng file này để làm việc với Claude

Khi bắt đầu một buổi làm việc, dán phần "GIAI ĐOẠN X" đang làm dở vào prompt kèm câu hỏi cụ thể, ví dụ:

```
Tôi đang ở Giai đoạn 3, Task 3 (đo jitter control loop) trong kế hoạch PROJECT_PLAN.md.
Tôi đã có control loop chạy ở SCHED_FIFO nhưng chưa biết cách log timestamp
chính xác để tính jitter. Hãy giúp tôi viết đoạn code đo và tính max/avg deviation.
```

Sau mỗi giai đoạn hoàn thành, có thể nhờ Claude review lại deliverable trước khi qua giai đoạn tiếp theo.
