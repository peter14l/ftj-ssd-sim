# FTJ Memory Engine Simulator - API Specification

This document specifies the public and internal C++20 API interfaces for the FTJ Memory Controller and Latency Injection subsystems.

---

## 1. Core Types and Structures

### 1.1 Command Types
```cpp
enum class Opcode : uint8_t {
    Read = 0x00,
    Write = 0x01,
    Flush = 0x02
};

struct QueueEntry {
    uint64_t command_id;
    Opcode opcode;
    uint64_t address;
    uint32_t length;
    void* buffer;
};

struct CompletionEntry {
    uint64_t command_id;
    int32_t status; // 0 for success, negative for errors
};
```

---

## 2. Memory Physics Model & Controller Interface

### 2.1 Class `FtjMemoryController`
Manages the simulated physical byte array representing the FTJ device.

```cpp
class FtjMemoryController {
public:
    // Initializes the backing memory allocation of simulated size
    explicit FtjMemoryController(size_t capacity_bytes);
    ~FtjMemoryController();

    // Prevent copying
    FtjMemoryController(const FtjMemoryController&) = delete;
    FtjMemoryController& operator=(const FtjMemoryController&) = delete;

    // Direct synchronous access methods
    int ReadSync(uint64_t address, void* dest_buffer, size_t size_bytes);
    int WriteSync(uint64_t address, const void* src_buffer, size_t size_bytes);

    size_t GetCapacity() const noexcept;
};
```

---

## 3. Latency Injection Interface

To accurately model 8ns latencies under a standard operating system (where `std::this_thread::sleep_for` has millisecond/microsecond resolution), we utilize high-precision hardware counters or simulated event clocks.

### 3.1 Class `LatencyInjector`
```cpp
class LatencyInjector {
public:
    // Configures the baseline latency in nanoseconds (default: 8ns)
    explicit LatencyInjector(uint64_t latency_ns = 8);

    // Injects the physical latency using a high-precision busy-wait loop
    // (QueryPerformanceCounter on Windows) or thread yielding.
    void Inject() const noexcept;

    // Alternative: Simulates logical timestamp progression for asynchronous modeling
    uint64_t SimulateLatency(uint64_t start_time_ns) const noexcept;
};
```

---

## 4. NVMe Queue Interfaces

### 4.1 Class `NvmeQueuePair`
A thread-safe circular ring buffer interface representing a single Submission/Completion Queue Pair.

```cpp
class NvmeQueuePair {
public:
    NvmeQueuePair(uint32_t queue_id, uint32_t depth);
    ~NvmeQueuePair();

    // Client submission and completion polling
    bool SubmitCommand(const QueueEntry& entry);
    bool PollCompletion(CompletionEntry& completion);

    // Backend worker processing interface
    bool PopCommand(QueueEntry& entry);
    bool PushCompletion(const CompletionEntry& completion);
};
```
