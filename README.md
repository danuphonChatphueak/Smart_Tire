# 🛞 Smart Tire AI — คู่มือการรันระบบ

ระบบวัดความลึกดอกยางและอ่าน DOT code ด้วย AI ประกอบด้วย 3 ส่วนหลัก:

| ส่วน | เทคโนโลยี | โฟลเดอร์ |
|------|-----------|----------|
| **Backend API** | Python FastAPI + YOLO | `backend/` |
| **Mobile App** | Flutter (Android/iOS) | `smart-tire/` |
| **Admin Web** | HTML/JS | `smart-tire-admin-web/` |

---

## 📋 ความต้องการของระบบ

- **Python** 3.10 หรือสูงกว่า
- **Flutter** SDK 3.x
- **Android Studio** หรือ **VS Code** (สำหรับ Flutter)
- **pip** (Python package manager)

---

## 🔧 1. Backend (FastAPI)

### โครงสร้าง Model Files

ไฟล์ model ทั้งหมดต้องอยู่ใน `backend/app/models/`:

```
backend/app/models/
├── mask.pt              ← YOLO สำหรับวัดความลึกดอกยาง (gap-pixel)
├── det_tire_code.pt     ← YOLO สำหรับ detect DOT/Size code
├── rec_tire_code.pth    ← CRNN สำหรับ recognize ตัวอักษร
└── model_final.pt       ← (optional) depth model เก่า
```

### ขั้นตอนการรัน (Windows)

```bat
cd backend
```

**วิธีที่ 1 — ใช้ `run.bat` (แนะนำ)**
```bat
run.bat
```
Script จะสร้าง virtualenv, ติดตั้ง dependencies และรัน server อัตโนมัติ

**วิธีที่ 2 — รันเอง**
```bat
python -m venv .venv
.venv\Scripts\activate

pip install -r requirements.txt

copy .env.example .env
rem แก้ไข .env ตามต้องการ

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### การตั้งค่า `.env`

เปิดไฟล์ `backend/.env` แล้วปรับค่าตามต้องการ:

```env
# Device สำหรับ AI (ใช้ cpu หรือ cuda)
infer_device=cpu

# Path ของ model files
det_model_path=app/models/det_tire_code.pt
rec_model_path=app/models/rec_tire_code.pth
mask_model_path=app/models/mask.pt

# Calibration ของ gap-pixel formula: depth = A * ln(gap_px) + B
# ปรับค่านี้หลังจาก run g.py เพื่อ calibrate แล้ว
gap_calib_a=2.85
gap_calib_b=-8.10

# Filtering thresholds (ปกติไม่ต้องแก้)
gap_min_count=10
gap_min_px=60.0
gap_max_px=200.0
gap_max_cv=0.18
gap_max_mad=10.0
gap_min_depth_mm=1.6
gap_max_depth_mm=8.5
```

### ตรวจสอบว่า Backend รันได้

เปิด browser ไปที่:
- **API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/api/infer/scan (POST)

---

## 📱 2. Mobile App (Flutter)

### ติดตั้ง Dependencies

```bash
cd smart-tire
flutter pub get
```

### ตั้งค่า API URL

เปิดไฟล์ที่เก็บ `baseUrl` (ปกติอยู่ใน `lib/core/api.dart` หรือ `lib/services/api_service.dart`) แล้วเปลี่ยน IP เป็น IP ของเครื่องที่รัน Backend:

```dart
static const String baseUrl = 'http://192.168.x.x:8000';
```

> ⚠️ **สำคัญ**: ใช้ IP จริงของเครื่อง ไม่ใช่ `localhost` เพราะ Android emulator ใช้ `10.0.2.2` แทน

### รันบน Android Emulator

```bash
flutter run
```

### รันบน Physical Device

```bash
flutter run --release
```

### Build APK

```bash
flutter build apk --release
```
APK จะอยู่ที่ `smart-tire/build/app/outputs/flutter-apk/app-release.apk`

---

## 🌐 3. Admin Web

```bash
cd smart-tire-admin-web
```

เปิดไฟล์ `index.html` ใน browser โดยตรง หรือใช้ live server:

```bash
# ใช้ Python simple server
python -m http.server 3000
```

แล้วเปิด http://localhost:3000

---

## 🧪 4. Calibration Tool (`g.py`)

ใช้สำหรับ calibrate ค่า `A` และ `B` ของสูตร `depth = A * ln(gap_px) + B` ด้วยชุดภาพ ground truth

### โครงสร้างไฟล์ที่ต้องเตรียม

```
smart-tire-2/
├── mask.pt         ← YOLO model
├── x/              ← โฟลเดอร์ภาพ input (jpg/png)
│   ├── img1.jpg
│   └── img2.jpg
└── gt.csv          ← Ground truth (ต้องมี column: image, true_depth)
```

ตัวอย่าง `gt.csv`:
```csv
image,true_depth
img1.jpg,3.5
img2.jpg,5.2
```

### รัน

```bash
cd c:\for_programer\smart-tire-2
python -m venv .venv
.venv\Scripts\activate
pip install ultralytics opencv-python numpy scipy

python g.py
```

ผลลัพธ์จะแสดง:
```
Calibrated: depth = 2.8432 * ln(px) + -8.0921
```

นำค่า `A` และ `B` ไปใส่ใน `backend/.env`:
```env
gap_calib_a=2.8432
gap_calib_b=-8.0921
```

แล้ว restart backend

---

## 🏗️ สถาปัตยกรรมระบบ

```
[Mobile App]
     │  POST /api/infer/scan
     │  mode=tread  →  image file
     ▼
[Backend FastAPI]
     │
     ├── mask_model (mask.pt)        ← YOLO-Seg แยก top/bottom mask
     │      ↓
     │   scan 150 vertical columns
     │      ↓
     │   gap_px = bottom_edge - top_edge
     │      ↓
     │   filter: CV < 0.18, MAD < 10px
     │      ↓
     │   depth_mm = A * ln(median_gap) + B
     │
     └── returns {"depthMm": {"value": 4.5, "conf": 0.8}}
```

---

## 🐛 แก้ปัญหาที่พบบ่อย

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| `FileNotFoundError: mask.pt` | ไม่มีไฟล์ model | copy `mask.pt` ไปไว้ที่ `backend/app/models/` |
| `depthMm: 0` ทุกภาพ | ไม่ผ่าน gap filter | ตรวจสอบ `gap_min_px`, `gap_max_px` ใน `.env` |
| Flutter ต่อ API ไม่ได้ | baseUrl ผิด | ใช้ IP จริงแทน localhost |
| CUDA error | GPU ไม่พร้อม | ตั้ง `infer_device=cpu` ใน `.env` |
