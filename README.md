# Azure VM (AzureObf)

<div align="center">

```text
       ___                             ____  __      ____  
      /   | ____  __  __________      / __ \/ /_    / __/  
     / /| |/_  / / / / / ___/ _ \    / / / / __ \  / /_    
    / ___ | / /_/ /_/ / /  /  __/   / /_/ / /_/ / / __/    
   /_/  |_|/___/\__,_/_/   \___/    \____/_.___(_)_/       
```

**Elite Lua / Luau Polymorphic Virtualization & Obfuscation Engine**  
*Custom ISA • Rolling Keystream • Anti-Hook • Opaque Math • Luraph v14.7 & v15.2 Cloaking*

[![Lua 5.1](https://img.shields.io/badge/Lua-5.1-blue.svg)](https://www.lua.org/)
[![Luau](https://img.shields.io/badge/Luau-Compatible-brightgreen.svg)](https://luau-lang.org/)
[![Roblox](https://img.shields.io/badge/Roblox-Mobile%20%26%20PC-red.svg)](https://www.roblox.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Base: Prometheus](https://img.shields.io/badge/Base%20Library-Prometheus-blueviolet.svg)](https://github.com/prometheus-lua/Prometheus)

</div>

---

## 📌 Lời cảm ơn & Nguồn gốc thư viện (Attribution)

> [!IMPORTANT]
> **Base Library Notice:**  
> Dự án **Azure VM** được phát triển và mở rộng dựa trên nền tảng mã nguồn mở xuất sắc của **[Prometheus Lua Obfuscator](https://github.com/prometheus-lua/Prometheus)** do tác giả **levno-710** sáng lập.
>
> - **Prometheus Core:** Cung cấp hạ tầng Parser, Lexer, Abstract Syntax Tree (AST), Scope Resolver, Unparser và kiến trúc Pipeline biến đổi code linh hoạt.
> - **Azure VM Engine:** Được đội ngũ phát triển mở rộng thêm tầng biên dịch Bytecode đa hình (Polymorphic Bytecode Compiler), bộ máy ảo máy con tùy biến (Virtual Machine Runtime Generator), mã hóa dòng Rolling Keystream Cipher, bẫy Decoy Opcodes, bẫy Anti-Debug / Anti-Tamper chuyên sâu cho môi trường Roblox, tối ưu hóa giải mã Base85 tốc độ cao không gây đứng hình (zero-lag), và kỹ thuật giả lập cấu trúc Luraph v14.7 / v15.2 (Luraph Cloaking).

---

## 🌟 Tính năng nổi bật (Key Features)

### 1. 🛡️ Ngụy trang cấu trúc Luraph v14.7 & v15.2 (Luraph Cloaking)
- **Chuẩn Single-Line 1 Dòng Code:** Output được gói gọn trong cấu trúc `return(function(...) ... end)(...);` đúng 1 dòng duy nhất (tương tự mẫu script thực tế của Luraph như `legendary.lua`), không dùng wrapper `setfenv` 3 lớp cồng kềnh.
- **Table-Based Dispatch Loop:** Trình thực thi VM sử dụng bảng dispatch động (ví dụ `_D[op](_R, a, b, c, bx, sbx)`), loại bỏ hoàn toàn các chuỗi `if-elseif` nhận diện đặc trưng của các bộ obf thông thường.
- **Luraph Markers & Signature Injection:** Rải đồng bộ các marker nhận diện phiên bản (`_LPH_OBFUSCATED`, `_LPH_JIT_MAX`, `_LPH_JIT_ULTRA`, `_LPH_HOOK_GUARD`, `_LPH_CRASH`, `_LPH_SIGNATURE`, `_LPH_ENCKEY`, ...).
- **Decoy Opcode Traps:** Chèn các hàm opcode mồi với toán tử toán học mờ (opaque math) để đánh lừa các công cụ phân tích tĩnh (static analysis) và deobfuscator tự động.

### 2. ⚡ Tối ưu hóa siêu tốc cho Roblox Executor (Zero-Lag Decompression)
- Bảng tra cứu trước `v[c] = string.char(c)` từ 0..255 giúp giải nén payload bytecode trong vòng **1-3 mili-giây**.
- **Không gây giật lag hoặc treo máy (no freeze):** Tương thích hoàn hảo với các Roblox Mobile/PC Executor (Delta, Fluxus, Codex, Arceus X, Solara, Wave,...). Luồng thực thi Roblox không bao giờ bị nghẽn (script watchdog timeout).

### 3. 🔒 Hệ thống Anti-Debug & Anti-Tamper chuyên sâu
- **Kiểm tra C-Closure Integrity:** Quét tính toàn vẹn của các hàm nguyên thủy `pcall`, `type`, `tostring`, `islclosure`, `isfunctionhooked`.
- **Callstack & Function Spy Detector:** Bẫy `debug.getinfo`, phát hiện các công cụ gián điệp callstack và tracer (`debug.traceback` chứa chuỗi `"hook"` hoặc `"spy"`).
- **Hook Guard & Coroutine Probe:** Tự động kích hoạt cơ chế tự hủy / vô hiệu hóa payload nếu phát hiện môi trường debug hoặc giả mạo con trỏ hàm.

### 4. 🔀 Tách biệt Open Upvalues (`__OPENUVS`)
- Triệt tiêu hoàn toàn lỗi rò rỉ scope hoặc ghi đè upvalue cha khi hàm con đóng upvalue (`__CLOSEUV`), bảo đảm 100% tính chính xác của các closure lồng nhau sâu.

### 5. 🏷️ Tùy biến Header thương hiệu (Custom Header)
- Mặc định:
  - Preset v14: `-- This file was protected using Azure VM v14.7 [Protected]`
  - Preset v15: `-- This file was protected using Azure VM v15.2 [Protected]`
- Hỗ trợ tham số `--header "<nội dung>"` để đổi thành bất kỳ tiêu đề nào (ví dụ `--header "Azure VM"`).

---

## 📊 Bảng Presets bảo vệ (Profiles)

| Preset | Kiến trúc VM | Tầng AST Pre-Mutation | Mức độ bảo vệ | Mục đích sử dụng |
| :--- | :--- | :--- | :--- | :--- |
| **`Luraph`** | AzureVM v14.7 Classic | Không | ⭐⭐⭐⭐ | VM thuần túy, dung lượng nhẹ nhất, load cực nhanh |
| **`Luraph14`** | AzureVM v14.7 Classic | Chuỗi & Số (Encrypt + Split) | ⭐⭐⭐⭐⭐ | Bảo vệ toàn diện cho script Roblox tiêu chuẩn |
| **`Luraph15`** | AzureVM v15.2 Ultra | Chuỗi & Số + Decoy 1.2x | ⭐⭐⭐⭐⭐+ | VM v15 nâng cao, kiểm tra Call Stack Depth |
| **`AzureGod`** | AzureVM v14.7 Classic | AST Pre-Mutation + VM | ⭐⭐⭐⭐⭐⭐ | Kết hợp biến đổi AST sâu trước khi nén vào VM |
| **`AzureGod15`** | AzureVM v15.2 Ultra | Full AST Pipeline + VM v15 (Decoy 1.5x) | 👑 **Tối Thượng** | Chống Deobf và dịch ngược mức độ cao nhất |

---

## 🚀 Hướng dẫn cài đặt & Sử dụng

### 1. Yêu cầu môi trường
- **Lua 5.1** hoặc **LuaJIT** hoặc **Luau** (đã cài đặt trên Linux, Termux, Windows, hoặc macOS).

### 2. Cú pháp dòng lệnh (CLI)
```bash
lua azure_obf.lua <input.lua> [options]
```

### 3. Danh sách các tham số (Options)
```text
  -o, --out <file>       File đầu ra (mặc định: <input>_protected.lua)
  --preset <name>        Chọn cấu hình bảo vệ (Luraph, Luraph14, Luraph15, AzureGod, AzureGod15)
  --header <text>        Tùy biến tiêu đề comment đầu file (mặc định: Azure VM v14.7/v15.2)
  --seed <number>        Cố định hạt giống PRNG để sinh mã tất định
  -v, --version          Hiển thị thông tin phiên bản
  -h, --help             Hiển thị menu trợ giúp
```

### 4. Ví dụ thực tế
```bash
# 1. Bảo vệ script với preset Luraph v14.7 mặc định:
lua azure_obf.lua script.lua -o script_obf.lua

# 2. Sử dụng preset cao cấp Luraph15:
lua azure_obf.lua main.lua --preset Luraph15 -o main_obf.lua

# 3. Sử dụng cấu hình tối thượng AzureGod15 với seed cố định:
lua azure_obf.lua game.lua --preset AzureGod15 --seed 1337 -o game_obf.lua

# 4. Tùy biến tiêu đề header theo ý muốn:
lua azure_obf.lua script.lua --preset Luraph14 --header "Azure VM" -o out.lua
```

---

## 📁 Cấu trúc thư mục dự án (Project Structure)

```text
AzureVM/
├── azure_obf.lua           # CLI Entrypoint chính
├── README.md               # Tài liệu hướng dẫn sử dụng & giới thiệu
├── LICENSE                 # Giấy phép MIT License (bao gồm attribution)
├── .gitignore              # Bộ lọc file tạm & build
├── examples/               # Các script mẫu kiểm thử
│   └── demo.lua            # Demo script với closure, math, upvalues
└── src/                    # Mã nguồn lõi (Prometheus Core + AzureVM)
    ├── presets.lua         # Cấu hình các preset bảo vệ
    ├── config.lua          # Cấu hình runtime
    ├── logger.lua          # Hệ thống ghi log
    └── prometheus/
        ├── azure_vm/       # Lõi Azure VM Generator & Encoder
        │   ├── generator.lua   # Trình sinh VM Runtime & Single-line emitter
        │   ├── reader.lua      # Bytecode Parser
        │   ├── encoder.lua     # Polymorphic Opcode & Keystream Encryptor
        │   ├── transpiler.lua  # Luau to Lua 5.1 Transpiler
        │   └── init.lua        # Entry module của AzureVM
        ├── steps/          # Các bước biến đổi (AzureVM, EncryptStrings, v.v.)
        │   └── AzureVM.lua     # Step tích hợp AzureVM vào Pipeline
        ├── compiler/       # Compiler AST Prometheus
        ├── parser.lua      # Lua/Luau Parser
        ├── pipeline.lua    # Pipeline biến đổi
        └── unparser.lua    # AST Unparser
```

---

## 📜 Giấy phép & Bản quyền (License & Credits)

Dự án được phân phối dưới giấy phép **MIT License**.

- **Prometheus Lua Obfuscator:** Bản quyền thuộc về [levno-710](https://github.com/prometheus-lua) (MIT License).
- **Azure VM Additions & Cloaking:** Bản quyền thuộc về **Azure** (2026).
