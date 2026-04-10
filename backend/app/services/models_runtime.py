# app/services/models_runtime.py
from __future__ import annotations

import collections
import base64
import math
import os
from dataclasses import dataclass
from typing import Optional, Tuple, List, Any

import cv2
import numpy as np
import torch
import inspect
import torch.nn as nn
import torch.nn.functional as F
from ultralytics import YOLO
import torchvision.transforms as T
from PIL import Image
from transformers import SegformerConfig, SegformerForSemanticSegmentation

from app.core.config import settings


class BidirectionalLSTM(nn.Module):
    def __init__(self, input_size: int, hidden_size: int, output_size: int):
        super().__init__()
        self.rnn = nn.LSTM(input_size, hidden_size, bidirectional=True)
        self.embedding = nn.Linear(hidden_size * 2, output_size)

    def forward(self, x):
        out, _ = self.rnn(x)
        T, B, _ = out.size()
        out = self.embedding(out.view(T * B, -1))
        return out.view(T, B, -1)


class CRNN(nn.Module):
    def __init__(self, nc: int = 1, num_classes: int = 37,
                 hidden_size: int = 256):
        super().__init__()
        self.cnn = nn.Sequential(
            # idx 0-2
            nn.Conv2d(nc, 64, 3, 1, 1), nn.ReLU(True), nn.MaxPool2d(2, 2),
            # idx 3-5
            nn.Conv2d(64, 128, 3, 1, 1), nn.ReLU(True), nn.MaxPool2d(2, 2),
            # idx 6-7
            nn.Conv2d(128, 256, 3, 1, 1), nn.ReLU(True),
            # idx 8-10
            nn.Conv2d(256, 256, 3, 1, 1), nn.ReLU(True),
            nn.MaxPool2d((2, 2), (2, 1), (0, 1)),
            # idx 11-13
            nn.Conv2d(256, 512, 3, 1, 1), nn.BatchNorm2d(512), nn.ReLU(True),
            # idx 14-16
            nn.Conv2d(512, 512, 3, 1, 1), nn.ReLU(True),
            nn.MaxPool2d((2, 2), (2, 1), (0, 1)),
            # idx 17-19
            nn.Conv2d(512, 512, 2, 1, 0), nn.BatchNorm2d(512), nn.ReLU(True),
        )
        self.rnn = nn.Sequential(
            BidirectionalLSTM(512, hidden_size, hidden_size),
            BidirectionalLSTM(hidden_size, hidden_size, num_classes),
        )

    def forward(self, x):
        conv = self.cnn(x)                        # (B, C, H', W')
        b, c, h, w = conv.size()
        # ถ้า H' > 1 ให้ adaptive pool เหลือ 1
        if h != 1:
            conv = nn.functional.adaptive_avg_pool2d(conv, (1, w))
        conv = conv.squeeze(2).permute(2, 0, 1)   # (W, B, C)
        out = self.rnn(conv)                       # (T, B, num_classes)
        return out



class TireSegDepthModel(nn.Module):
    def __init__(self, backbone: str = "nvidia/mit-b2"):
        super().__init__()
        # We assume the model is loaded via state_dict later, 
        # but we need the architecture from the config.
        # Original snippet uses from_pretrained, but here we might need to handle local loading.
        config = SegformerConfig.from_pretrained(backbone)
        base = SegformerForSemanticSegmentation(config)
        
        self.encoder = base.segformer
        chs = base.config.hidden_sizes
        fusion_in = chs[-2] + chs[-1]
        out_ch = chs[-1]
        self.reduce = nn.Conv2d(fusion_in, out_ch, 3, padding=1)
        self.seg_head = nn.Conv2d(out_ch, 1, 1)
        self.scalar_mlp = nn.Sequential(
            nn.Linear(out_ch, 128), nn.GELU(), nn.Linear(128, 1)
        )

    def forward(self, x: torch.Tensor, mask: Optional[torch.Tensor] = None) -> Tuple[torch.Tensor, torch.Tensor]:
        out = self.encoder(pixel_values=x, output_hidden_states=True)
        mid, last = out.hidden_states[-2], out.hidden_states[-1]
        
        def to_spatial(t: torch.Tensor) -> torch.Tensor:
            if t.ndim == 3:
                B, N, C = t.shape
                H = int(math.sqrt(float(N)))
                return t.permute(0, 2, 1).reshape(B, C, H, H)
            return t

        mid, last = to_spatial(mid), to_spatial(last)
        if mid.shape[2:] != last.shape[2:]:
            target_h, target_w = max(mid.shape[2], last.shape[2]), max(mid.shape[3], last.shape[3])
            mid = F.interpolate(mid, size=(target_h, target_w), mode="bilinear", align_corners=False)
            last = F.interpolate(last, size=(target_h, target_w), mode="bilinear", align_corners=False)

        fused = torch.cat([mid, last], dim=1)
        fused = self.reduce(fused)
        seg = F.interpolate(self.seg_head(fused), size=x.shape[2:], mode="bilinear", align_corners=False)
        pooled = fused.mean(dim=[2, 3])
        scalar = self.scalar_mlp(pooled)
        return seg, scalar






def _build_model_from_state_dict(sd: dict, charset_len: int) -> nn.Module:
    """
    สร้าง CRNN จาก state_dict — ถ้า load_state_dict ไม่ผ่าน จะ print keys ทั้งหมดเพื่อ debug
    """
    num_classes = charset_len + 1

    # อ่าน hidden_size จาก LSTM weight_hh
    hidden_size = 256
    for k, v in sd.items():
        if "rnn" in k and "weight_hh" in k:
            hidden_size = v.shape[1]
            break

    model = CRNN(nc=1, num_classes=num_classes, hidden_size=hidden_size)

    try:
        model.load_state_dict(sd, strict=True)
        print("[ModelsRuntime] ✅ CRNN state_dict loaded (strict)")
        return model
    except RuntimeError:
        pass

    # strict=True ไม่ผ่าน → ลอง strict=False
    try:
        model.load_state_dict(sd, strict=False)
        print("[ModelsRuntime] ⚠️ CRNN state_dict loaded (strict=False, some keys may be missing)")
        return model
    except RuntimeError as e:
        # ถ้ายังไม่ผ่านเลย → print keys ทั้งหมดเพื่อ debug
        print("[ModelsRuntime] ❌ Cannot load CRNN state_dict. Keys in checkpoint:")
        for k, v in sd.items():
            print(f"  {k:50s} {str(v.shape):>30s}")
        print(f"\n[ModelsRuntime] Expected keys from CRNN model:")
        for k, v in model.state_dict().items():
            print(f"  {k:50s} {str(v.shape):>30s}")
        raise e


@dataclass
class DetResult:
    xyxy: Tuple[int, int, int, int]
    conf: float
    polygon: Optional[np.ndarray] = None  # (N, 2) int32


class ModelsRuntime:
    """
    โหลดโมเดลครั้งเดียว แล้วเรียกใช้ใน endpoints
    - det: YOLO (.pt) class = dotcode
    - rec: CRNN (.pth) + CTC greedy decode
    - depth: (.pth) output เป็น mm ตรง ๆ
    """

    def __init__(self):
        # device
        dev = str(settings.infer_device).lower()
        if dev.startswith("cuda") and not torch.cuda.is_available():
            dev = "cpu"
        self.device = dev

        # paths
        self.det_path = settings.det_model_path
        self.rec_path = settings.rec_model_path
        self.depth_path = settings.depth_model_path

        self.use_internal_recog = bool(settings.use_internal_recog)

        # charset (ไม่รวม blank; blank=0)
        self.charset = list(str(settings.crnn_charset))

        self.det: Optional[YOLO] = None
        self.rec: Optional[torch.nn.Module] = None
        self.depth: Optional[torch.nn.Module] = None
        self.calib_a = 1.0
        self.calib_b = 0.0

        self._load_all()

    def _load_all(self):
        """
        PyTorch 2.6+ จะ default weights_only=True ทำให้ Ultralytics .pt โหลดไม่ผ่าน
        เรา patch torch.load ชั่วคราวให้ weights_only=False เฉพาะตอน YOLO(self.det_path)
        """
        import torch  # local import กันชน

        # =========================
        # ✅ PATCH torch.load (สำคัญมาก)
        # =========================
        _orig_torch_load = torch.load

        def _torch_load_compat(*args, **kwargs):
            if "weights_only" not in kwargs:
                kwargs["weights_only"] = False
            return _orig_torch_load(*args, **kwargs)

        torch.load = _torch_load_compat
        try:
            # 1) YOLO Detection
            self.det = YOLO(self.det_path)
        finally:
            torch.load = _orig_torch_load

        # 2) Recognition (CRNN)
        # Check if torch.load supports weights_only
        load_kwargs = {"map_location": self.device}
        if "weights_only" in inspect.signature(torch.load).parameters:
            load_kwargs["weights_only"] = False

        rec_obj = torch.load(self.rec_path, **load_kwargs)

        if isinstance(rec_obj, torch.nn.Module):
            self.rec = rec_obj
        elif isinstance(rec_obj, (dict, collections.OrderedDict)):
            # state_dict → สร้าง CRNN model แล้วโหลด weights
            print("[ModelsRuntime] rec model is state_dict, building CRNN...")
            self.rec = _build_model_from_state_dict(rec_obj, len(self.charset))
        else:
            raise TypeError(f"Unexpected rec model type: {type(rec_obj)}")
        self.rec.to(self.device)
        self.rec.eval()

        # 3) Depth
        # Load calibration coefficients
        calib_path = os.path.join(os.path.dirname(self.depth_path), "calibration.npz")
        if os.path.exists(calib_path):
            try:
                cal = np.load(calib_path)
                self.calib_a = float(cal['a'])
                self.calib_b = float(cal['b'])
                print(f"[ModelsRuntime] Loaded calibration: a={self.calib_a}, b={self.calib_b}")
            except Exception as e:
                print(f"[ModelsRuntime] Warning: Could not load calibration coefficients: {e}")

        # The new model architecture: TireSegDepthModel
        # Based on user snippet, we should load from settings.depth_model_path which is now model_final.pt
        # Or we can check if it's the old depth_tire.pt. 
        # User said files are in backend/app/models. 
        # Let's check for model_final.pt specifically.
        model_final_path = os.path.join(os.path.dirname(self.depth_path), "model_final.pt")
        target_path = model_final_path if os.path.exists(model_final_path) else self.depth_path

        print(f"[ModelsRuntime] Loading depth model from {target_path}...")
        
        # Load weights
        depth_obj = torch.load(
            target_path,
            map_location=self.device,
            weights_only=False,
        )

        # Build architecture
        self.depth = TireSegDepthModel().to(self.device)
        
        if isinstance(depth_obj, torch.nn.Module):
            self.depth = depth_obj
        elif isinstance(depth_obj, (dict, collections.OrderedDict)):
            self.depth.load_state_dict(depth_obj, strict=False)
            print(f"[ModelsRuntime] ✅ TireSegDepthModel loaded from state_dict")
        else:
            raise TypeError(f"Unexpected depth model type: {type(depth_obj)}")
        
        self.depth.to(self.device)
        self.depth.eval()

    # ---------- 1) DETECTION ----------
    def detect_code_box(self, bgr: np.ndarray, conf_thres: float = 0.25) -> Tuple[dict[str, Optional[DetResult]], bool]:
        """
        Detect 'dotcode' and 'sizecode'.
        Returns (dict, rotated_flag): 
          - dict: {"tire_code": DetResult|None, "size_code": DetResult|None}
          - rotated_flag: bool (True if image was rotated 180 to find result)
        If no valid detections > conf_thres, rotate image 180 and try again.
        """
        assert self.det is not None

        def _run_det(img, rot_180=False):
             # Run inference
            results = self.det(img, conf=conf_thres, verbose=False)
            
            # Map class names to our keys
            # Assumption: Class 0 = dotcode/tire_code, Class 1 = sizecode
            # We will try to map by name if available, else index
            names = getattr(self.det, "names", {})
            
            found = {"tire_code": None, "size_code": None}
            
            for r in results:
                if r.boxes is None or len(r.boxes) == 0:
                    continue

                xyxy_list = r.boxes.xyxy.cpu().numpy()
                confs_list = r.boxes.conf.cpu().numpy()
                clss_list = r.boxes.cls.cpu().numpy().astype(int)
                
                # Check for masks
                masks_list = None
                if r.masks is not None:
                    masks_list = r.masks.xy

                for i, (box, c, cls_id) in enumerate(zip(xyxy_list, confs_list, clss_list)):
                    if c < conf_thres:
                        continue

                    # Mapping based on user request:
                    # 1 (or 'dotcode') -> tire_code
                    # 0 (or 'Size_code') -> size_code
                    
                    cls_name = names.get(cls_id, str(cls_id)).lower()
                    target_key = None
                    
                    # 1. Check by Name (safest if model has names)
                    if "dotcode" in cls_name or "tire_code" in cls_name:
                        target_key = "tire_code"
                    elif "size" in cls_name: # matches 'Size_code'
                        target_key = "size_code"
                    
                    # 2. Fallback by ID if name didn't match specific keys
                    if target_key is None:
                        if cls_id == 1:
                            target_key = "tire_code"
                        elif cls_id == 0:
                            target_key = "size_code"
                    
                    if target_key:
                        x1, y1, x2, y2 = box.astype(int).tolist()
                        
                        # Fix coordinates if rotated
                        if rot_180:
                            h, w = img.shape[:2]
                            # 180 degree rotation: (x, y) -> (w-x, h-y)
                            # But wait, we passed rotated image to model. Box is in rotated coords.
                            # We need to rotate box back to original coords?
                            # Actually, simplest is to rotate the crop later. 
                            # But here we want to return box in ORIGINAL image coords?
                            # Let's keep it simple: return result indicating if it was found in rotated image.
                            pass

                        # Get polygon
                        poly = None
                        if masks_list is not None and i < len(masks_list):
                            poly = masks_list[i].astype(np.int32)
                        
                        # Keep best confidence
                        current = found[target_key]
                        if current is None or c > current.conf:
                            found[target_key] = DetResult((x1, y1, x2, y2), float(c), poly)
            return found

        # 1. Try original orientation
        res = _run_det(bgr)
        
        # 2. If nothing found, try rotating 180
        if res["tire_code"] is None and res["size_code"] is None:
            # Rotate 180
            bgr_180 = cv2.rotate(bgr, cv2.ROTATE_180)
            res_180 = _run_det(bgr_180, rot_180=True)
            
            if res_180["tire_code"] is not None or res_180["size_code"] is not None:
                # Found something in rotated image! 
                # We need to signal that the image should be rotated.
                # Or we can return the DET result on the ROTATED image, 
                # and caller must know to use the rotated image for cropping.
                # However, for simplicity, let's attach a flag or let the caller handle it?
                # Actually, `DetResult` stores coordinates. 
                # If we return coordinates for the rotated image, `crop` function needs the rotated image.
                # Let's add a `rotated` flag to DetResult? Or just return the rotated detections 
                # and let crop handle it if we pass the rotated image?
                # BETTER APPROACH: Return a tuple (results, is_rotated)
                return res_180, True
            
        return res, False

    def crop(self, bgr: np.ndarray, det_result: DetResult, pad: int = 6) -> np.ndarray:
        """
        Crop image based on detection result.
        If polygon is available, use it to get a tighter bounding rect (or rotate/warp if needed).
        For now, we'll use the bounding box of the polygon if present, else the detection box.
        """
        h, w = bgr.shape[:2]
        
        if det_result.polygon is not None and len(det_result.polygon) > 0:
            # ใช้ polygon หา bounding rect ใหม่ที่แม่นยำกว่า box ปกติของ YOLO (บางที YOLO box มันรวม shadow)
            x, y, w_poly, h_poly = cv2.boundingRect(det_result.polygon)
            x1 = x
            y1 = y
            x2 = x + w_poly
            y2 = y + h_poly
        else:
            x1, y1, x2, y2 = det_result.xyxy

        x1 = max(0, x1 - pad)
        y1 = max(0, y1 - pad)
        x2 = min(w - 1, x2 + pad)
        y2 = min(h - 1, y2 + pad)
        
        return bgr[y1:y2, x1:x2].copy()

    # ---------- CTC DECODE ----------
    def ctc_greedy_decode(self, probs: torch.Tensor) -> Tuple[str, float]:
        """
        probs: (T,C) หรือ (B,T,C) หลัง softmax
        CTC greedy: argmax ทีละเวลา แล้ว collapse + ลบ blank(0)
        """
        if probs.dim() == 3:
            probs = probs[0]  # (T, C)

        max_ids = torch.argmax(probs, dim=1).tolist()
        max_confs = torch.max(probs, dim=1).values.tolist()

        out = []
        out_confs = []
        prev = None
        for idx, cf in zip(max_ids, max_confs):
            if idx == 0:  # blank
                prev = idx
                continue
            if idx == prev:  # ซ้ำติดกัน
                continue
            prev = idx

            char_i = idx - 1  # เพราะ 0 คือ blank
            if 0 <= char_i < len(self.charset):
                out.append(self.charset[char_i])
                out_confs.append(float(cf))

        text = "".join(out)
        conf = float(sum(out_confs) / len(out_confs)) if out_confs else 0.0
        return text, conf

    # ---------- 2) RECOGNITION (CRNN) ----------
    def recognize_code(self, crop_bgr: np.ndarray) -> Tuple[str, float]:
        """
        CRNN + CTC greedy decode
        IMPORTANT: ถ้าโมเดลคุณ preprocess ต่างจากนี้ ให้ปรับตรงนี้
        """
        if not self.use_internal_recog:
            return ("", 0.0)

        assert self.rec is not None

        gray = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2GRAY)

        target_h = 64
        max_w = 256
        h, w = gray.shape[:2]
        scale = target_h / max(h, 1)
        new_w = int(w * scale)
        new_w = max(1, min(new_w, max_w))

        resized = cv2.resize(gray, (new_w, target_h))
        canvas = np.zeros((target_h, max_w), dtype=np.uint8)
        canvas[:, :new_w] = resized

        img = canvas.astype(np.float32) / 255.0
        img = (img - 0.5) / 0.5  # normalize

        tensor = torch.from_numpy(img)[None, None, :, :].to(self.device)  # (1,1,H,W)

        with torch.no_grad():
            out = self.rec(tensor)

        logits = out

        # รองรับรูปแบบยอดนิยม:
        # - (B,T,C) -> ใช้ได้เลย
        # - (T,B,C) -> permute เป็น (B,T,C)
        # - (B,C,T) -> permute เป็น (B,T,C)
        if isinstance(logits, torch.Tensor) and logits.dim() == 3:
            # (T,B,C) -> (B,T,C) ถ้า B=1
            if logits.shape[1] == 1 and logits.shape[0] > 1:
                logits = logits.permute(1, 0, 2)

            # (B,C,T) -> (B,T,C) (heuristic)
            if logits.shape[1] > 20 and logits.shape[2] <= 512:
                logits = logits.permute(0, 2, 1)

        probs = torch.softmax(logits, dim=-1)  # (B,T,C)
        return self.ctc_greedy_decode(probs)

    # ---------- 3) DEPTH ----------
    def predict_depth_mm(self, bgr: np.ndarray) -> Tuple[float, float]:
        """
        ฟังก์ชันนี้ใช้สำหรับการทำนายความลึกของดอกยางโดยใช้ TireSegDepthModel
        1. Preprocess: Resize 512x512, BGR->RGB, Normalize (ImageNet mean/std)
        2. Inference: model(input, dummy_mask)
        3. Postprocess: Apply calibration (a, b coeffs)
        """
        assert self.depth is not None

        # 1. Preprocess (ตาม User snippet)
        img_res = cv2.resize(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB), (512, 512))
        tensor = torch.from_numpy(img_res).permute(2, 0, 1).float() / 255.0
        mean = torch.tensor([0.485, 0.456, 0.406]).view(3, 1, 1).to(self.device)
        std = torch.tensor([0.229, 0.224, 0.225]).view(3, 1, 1).to(self.device)
        input_tensor = ((tensor.to(self.device) - mean) / std).unsqueeze(0)

        # 2. Dummy Mask (โมเดลบังคับรับ 2 parameters)
        dummy_mask = torch.zeros((1, 1, 512, 512)).to(self.device)

        with torch.no_grad():
            # โมเดลคืนค่า (seg_logits, depth_raw)
            seg_logits, depth_raw = self.depth(input_tensor, dummy_mask)
        
        # 3. ตรวจสอบพื้นที่ที่โมเดลตรวจพบ (Tread Validation)
        # ถ้าพื้นที่ที่ Mask ได้น้อยเกินไป (Threshold 1,000 พิกเซล) แสดงว่าอาจไม่ใช่รูปดอกยาง
        mask_prob = torch.sigmoid(seg_logits).squeeze()
        mask_area = (mask_prob > 0.5).sum().item()
        
        if mask_area < 1000: 
            print(f"[ModelsRuntime] Tread validation failed: mask_area={mask_area}")
            return 0.0, 0.0

        # 4. ดึงค่า raw value และใช้สูตร Calibration ตามแอพ (User: ใช้สูตรคำนวนตามแอพ)
        raw_val = float(depth_raw.detach().cpu().reshape(-1)[0].item())
        depth_mm = (raw_val * self.calib_a) + self.calib_b
        
        return depth_mm, 0.8


    # ---------- VALIDATION HLPER ----------
    def validate_dotcode(self, text: str) -> Optional[str]:
        """
        Validate Dotcode:
        - Must be exactly 4 digits.
        - First 2 digits (Week) <= 52.
        - Last 2 digits (Year) <= Current Year (e.g. 26).
        """
        import datetime
        
        # 1. Clean up (keep only digits)
        digits = "".join(filter(str.isdigit, text))
        
        # 2. Check length
        if len(digits) != 4:
            return None
            
        # 3. Parse components
        week = int(digits[:2])
        year = int(digits[2:])
        
        # 4. Check Week
        if not (1 <= week <= 52):
            return None
            
        # 5. Check Year
        # Get current year short format (e.g. 2026 -> 26)
        current_year = datetime.datetime.now().year % 100
        # Allow up to current year (or maybe +1 for buffers? user said <= current)
        if year > current_year:
            return None
            
        return digits

    # ---------- HIGH-LEVEL PREDICTION METHODS ----------
    
    def predict_sidewall(self, bgr: np.ndarray) -> dict:
        import re
        import base64
        import cv2
        from google.cloud import vision
        
        API_KEY = 'AIzaSyC-PK_n5OK7elRsmMFQPdyqzkpeNllbu-4'

        def _to_base64(img_bgr) -> str:
            if img_bgr is None or img_bgr.size == 0:
                return ""
            _, buf = cv2.imencode(".jpg", img_bgr)
            return base64.b64encode(buf).decode("utf-8")

        def _crop_region(img_bgr, boxes: list, pad: int = 16) -> str:
            """รวม bounding boxes แล้วตัดรูปพร้อม padding"""
            if not boxes:
                return ""
            h, w = img_bgr.shape[:2]
            x1 = max(0, min(b[0] for b in boxes) - pad)
            y1 = max(0, min(b[1] for b in boxes) - pad)
            x2 = min(w, max(b[2] for b in boxes) + pad)
            y2 = min(h, max(b[3] for b in boxes) + pad)
            crop = img_bgr[y1:y2, x1:x2]
            return _to_base64(crop)

        results = {
            "tire_code": {"text": "", "conf": 0.0, "image": None},
            "size_code": {"text": "", "conf": 0.0, "image": None},
            "rotated": False
        }

        try:
            client = vision.ImageAnnotatorClient(client_options={"api_key": API_KEY})
        except Exception as e:
            print(f"Error initializing vision client: {e}")
            return results

        success, encoded_image = cv2.imencode('.jpg', bgr)
        if not success:
            return results
        content = encoded_image.tobytes()

        image = vision.Image(content=content)

        try:
            response = client.text_detection(image=image)
            if response.error.message:
                print(f'เกิดข้อผิดพลาด: {response.error.message}')
                return results

            annotations = response.text_annotations
            if not annotations:
                return results

            # ── full text สำหรับ regex ──
            full_text = annotations[0].description if annotations else ''

            # ── สร้าง lookup: text → bounding box (x1,y1,x2,y2) ──
            ann_boxes = []  # [(text, x1, y1, x2, y2), ...]
            for ann in annotations[1:]:
                verts = ann.bounding_poly.vertices
                xs = [v.x for v in verts]
                ys = [v.y for v in verts]
                if not xs or not ys:
                    continue
                ann_boxes.append((ann.description, min(xs), min(ys), max(xs), max(ys)))

            # ── Regex หา DOT และ Size จาก full text ──
            # หา DOT แล้วตามด้วยกลุ่มตัวเลข 4 ตัวที่อยู่ท้ายที่สุดในระยะ 60 ตัวอักษร (Greedy match)
            dot_match = re.search(r'DOT[\s\S]{0,60}(\d{4})', full_text, re.IGNORECASE)
            size_match = re.search(r'\d{3}/\d{2}\s*R\s*\d{2}(?:\s*\d{2,3}[A-Z])?', full_text, re.IGNORECASE)

            dot_raw = dot_match.group(0) if dot_match else None
            size_raw = size_match.group(0) if size_match else None

            # ── หา bounding boxes ที่เกี่ยวข้องกับ DOT ──
            dot_crop_b64 = ""
            dot_digits = ""
            if dot_match:
                dot_digits = dot_match.group(1)

                dot_boxes = []
                for (t, x1, y1, x2, y2) in ann_boxes:
                    if re.search(r'DOT', t, re.IGNORECASE) or (
                        dot_digits and dot_digits in t
                    ) or re.search(r'\d{4}', t):
                        dot_boxes.append((x1, y1, x2, y2))

                if dot_boxes:
                    dot_crop_b64 = _crop_region(bgr, dot_boxes, pad=24)
                else:
                    dot_crop_b64 = _to_base64(bgr)

            # ── หา bounding boxes ที่เกี่ยวข้องกับ Size ──
            size_crop_b64 = ""
            if size_raw:
                size_boxes = []
                for (t, x1, y1, x2, y2) in ann_boxes:
                    t_clean = re.sub(r'\s+', '', t)
                    if re.search(r'\d{3}/\d{2}', t_clean) or re.search(r'R\d{2}', t_clean):
                        size_boxes.append((x1, y1, x2, y2))

                if size_boxes:
                    size_crop_b64 = _crop_region(bgr, size_boxes, pad=24)
                else:
                    size_crop_b64 = _to_base64(bgr)

            # ── Build results ──
            if dot_digits:
                results["tire_code"] = {
                    "text": dot_digits,
                    "conf": 1.0,
                    "raw_text": dot_raw,
                    "image": dot_crop_b64,
                }

            if size_raw:
                results["size_code"] = {
                    "text": size_raw,
                    "conf": 1.0,
                    "image": size_crop_b64,
                }

        except Exception as e:
            print(f"Vision API error: {e}")

        return results


    def _predict_sidewall_old(self, bgr: np.ndarray) -> dict:
        """
        Full pipeline for Sidewall:
        1. Detect -> Crop -> Recognize (Original)
        2. Validate Dotcode (Must be 4 digits)
        3. If Invalid -> Retry CRNN 5 times with jitter -> Pick Max Confidence
        4. If still invalid -> Rotate 180 -> Repeat
        5. Return best result
        """
        results = {
            "tire_code": {"text": "", "conf": 0.0, "image": None},
            "size_code": {"text": "", "conf": 0.0, "image": None},
            "rotated": False
        }
        
        def _to_base64(img_bgr) -> str:
            """Ensure img is BGR, encode as jpg base64 string"""
            if img_bgr is None or img_bgr.size == 0:
                return ""
            _, buf = cv2.imencode(".jpg", img_bgr)
            return base64.b64encode(buf).decode("utf-8")
        
        def _get_best_candidate(candidates):

            # Candidates = list of (cleaned_text, conf, raw_text)
            # Priority 1: len == 4
            valid_4 = [c for c in candidates if len(c[0]) == 4]
            if valid_4:
                return max(valid_4, key=lambda x: x[1])
            # Priority 2: Max conf
            if candidates:
                return max(candidates, key=lambda x: x[1])
            return ("", 0.0, "")

        # Helper to run pipeline on an image with retry logic
        def _run_pipeline(img):
            dets, _ = self.detect_code_box(img, conf_thres=0.25)
            
            res_tc = None
            res_sc = None
            
            # Process Tire Code (Dotcode)
            if dets["tire_code"]:
                # 1. First Attempt
                crop_0 = self.crop(img, dets["tire_code"], pad=6)
                text_0, conf_0 = self.recognize_code(crop_0)
                digits_0 = "".join(filter(str.isdigit, text_0))
                
                final_text = digits_0
                final_conf = conf_0
                final_raw = text_0
                
                # Rule: Force 4 chars. If not, loop 5 times.
                if len(digits_0) != 4:
                    candidates = [(digits_0, conf_0, text_0)]
                    
                    # Loop 5 times with jitter
                    # We can vary padding and/or slight offsets
                    for _ in range(5):
                        # Jitter: Random padding between 2 and 14 (default 6)
                        # And/or random shifts if we had a way to shift box without `crop` method changes
                        # For now, varying padding effectively changes zoom/context
                        pad_jitter = np.random.randint(2, 12)
                        
                        # Potentially add slight randomness to box coords if we had access, 
                        # but DetResult is fixed here. Modifying DetResult is cleaner.
                        # Let's clone det result
                        d = dets["tire_code"]
                        if d.xyxy:
                            x1, y1, x2, y2 = d.xyxy
                            # Random offset -2 to +2
                            ox = np.random.randint(-2, 3)
                            oy = np.random.randint(-2, 3)
                            
                            # Create a temp DetResult (hacky but works)
                            d_jitter = DetResult(
                                xyxy=(x1+ox, y1+oy, x2+ox, y2+oy),
                                conf=d.conf,
                                polygon=d.polygon # Polygon might be misaligned if we shift box, strictly we should shift polygon too but simple box shift is enough for OCR jitter
                            )
                            c_img = self.crop(img, d_jitter, pad=pad_jitter)
                            t, c = self.recognize_code(c_img)
                            dig = "".join(filter(str.isdigit, t))
                            candidates.append((dig, c, t))
                    
                    # Pick best
                    best_c = _get_best_candidate(candidates)
                    final_text, final_conf, final_raw = best_c

                # Get base64 image of the final crop (using the one that produced the best text if possible)
                # If we used jitter, the original crop might differ slightly, but sending the base crop is fine for display
                # Or re-crop if we picked a jittered one? 
                # For simplicity, let's send the original crop_0 (un-jittered) as the reference image
                # or better: send the crop that yielded the best result.
                # Since candidates store (text, conf, raw), we don't store the image.
                # Let's just send the `crop_0` (base crop) to user as "Detected Image".
                b64 = _to_base64(crop_0)

                res_tc = {"text": final_text, "conf": final_conf, "raw_text": final_raw, "image": b64}
                
            # Process Size Code (Normal logic)
            if dets["size_code"]:
                crop_sc = self.crop(img, dets["size_code"])
                text, conf = self.recognize_code(crop_sc)
                b64 = _to_base64(crop_sc)
                res_sc = {"text": text, "conf": conf, "image": b64}
                
            return res_tc, res_sc

        # Attempt 1: Original Orientation
        tc_1, sc_1 = _run_pipeline(bgr)
        
        is_valid_1 = False
        if tc_1 and len(tc_1["text"]) == 4:
             # validate digits logic (week <= 52, etc) can still apply?
             # User said "fix value .. force 4 chars". 
             # If I force 4 chars, do I still check semantic validity?
             # Safe bet: Check semantic validity if 4 chars.
             if self.validate_dotcode(tc_1["text"]):
                 is_valid_1 = True
        
        if is_valid_1:
            if tc_1: results["tire_code"] = tc_1
            if sc_1: results["size_code"] = sc_1
            return results

        # Attempt 2: Rotate 180
        bgr_180 = cv2.rotate(bgr, cv2.ROTATE_180)
        tc_2, sc_2 = _run_pipeline(bgr_180)
        
        is_valid_2 = False
        if tc_2 and len(tc_2["text"]) == 4:
             if self.validate_dotcode(tc_2["text"]):
                 is_valid_2 = True
        
        if is_valid_2:
            results["tire_code"] = tc_2 if tc_2 else results["tire_code"] 
            results["size_code"] = sc_2 if sc_2 else results["size_code"]
            results["rotated"] = True
            return results
            
        # Fallback: Best Effort
        # If neither is semantically valid 4-digit code, pick the one that at least has 4 digits?
        # Or highest conf?
        # Logic: Prefer result with 4 digits.
        
        picked_tc = None
        picked_sc = None
        is_rotated = False
        
        has_4_1 = tc_1 and len(tc_1["text"]) == 4
        has_4_2 = tc_2 and len(tc_2["text"]) == 4
        
        if has_4_1 and not has_4_2:
            picked_tc = tc_1
            picked_sc = sc_1
        elif has_4_2 and not has_4_1:
            picked_tc = tc_2
            picked_sc = sc_2
            is_rotated = True
        elif has_4_1 and has_4_2:
            # Both have 4 digits but failed validation (e.g. week 99)
            # Pick higher conf
            if tc_1["conf"] >= tc_2["conf"]:
                picked_tc = tc_1
                picked_sc = sc_1
            else:
                picked_tc = tc_2
                picked_sc = sc_2
                is_rotated = True
        else:
            # Neither has 4 digits. Pick max confidence or create empty?
            # User: "If no digits, empty."
            # We already filtered digits.
            if tc_1 and tc_2:
                if tc_1["conf"] >= tc_2["conf"]:
                    picked_tc = tc_1
                    picked_sc = sc_1
                else:
                    picked_tc = tc_2
                    picked_sc = sc_2
                    is_rotated = True
            elif tc_1:
                picked_tc = tc_1
                picked_sc = sc_1
            elif tc_2:
                picked_tc = tc_2
                picked_sc = sc_2
                is_rotated = True
                
        if picked_tc: results["tire_code"] = picked_tc
        if picked_sc: results["size_code"] = picked_sc
        results["rotated"] = is_rotated
        
        return results

    def predict_tread(self, bgr: np.ndarray) -> Optional[float]:
        """
        Full pipeline for Tread:
        ส่งรูปตรง ๆ เข้าโมเดลเลย ไม่มีการเตรียมรูปหรือหมุนซ้ำ
        """
        d, _ = self.predict_depth_mm(bgr)
        return d

# ---------------------------
# ✅ Lazy singleton (แนะนำ)
# ---------------------------
_RUNTIME: Optional[ModelsRuntime] = None


def get_runtime() -> ModelsRuntime:
    global _RUNTIME
    if _RUNTIME is None:
        _RUNTIME = ModelsRuntime()
    return _RUNTIME

