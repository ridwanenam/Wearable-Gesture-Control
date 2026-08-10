# Wearable Gesture Control Ecosystem ⌚🚀

[![Platform](https://shields.io)](https://flutter.dev)
[![Hardware](https://shields.io)](https://arduino.cc)
[![Framework](https://shields.io)](https://edgeimpulse.com)

An end-to-end wearable interaction ecosystem that enables hands-free multi-tab control using wrist micro-gestures. The project consists of two core components: a standalone smartwatch firmware powered by a deterministic, non-blocking time-domain heuristic state machine, and a cross-platform mobile client built with Flutter targeting Android 14.

This repository hosts the source code for both the **Arduino firmware Core** and the **Flutter monorepo application (`flutter_application_1`)**, developed at the PUI-PT Intelligent Sensing IoT Laboratory, Telkom University.

---

## 📸 System Previews

| Physical Smartwatch Hardware | Flutter Mobile HUD Interface |
|:---:|:---:|
| <img src="docs/physical_watch.png" width="300" alt="Hardware Prototype"> | <img src="docs/mobile_app_hud.png" width="220" alt="App HUD Screens"> |
| *Stacked Sandwich Assembly* | *Dashboard, Presentation, & Camera Tabs* |

---

## ⚡ Key Features

* **Heuristic Time-Domain FSM:** Rejects high-overhead neural networks to achieve near-zero edge computation latency on the RP2040 chip by monitoring a single absolute temporal acceleration gradient ($|\Delta y_t|$) locked firmly at 104 Hz.
* **Reactive Tab-Aware State Manager:** Multiplies the utility of a compact 4-class gesture set (`NEXT_TAP`, `PREV_TAP`, `NEXT_FIST`, `PREV_FIST`) across multi-page views using the Flutter `Provider` pattern.
* **Smart Presentation Mode ($\text{Tab} = 1$):** Spawns a high-throughput local HTTP/WebSocket server (via `shelf`) on Port 8080. Clones viewports using `RenderRepaintBoundary` with clear crisp-edges GPU texture pen sharpening for crisp, blur-free desktop presentation slide mirroring.
* **Smart Camera HUD ($\text{Tab} = 2$):** Binds gesture tokens directly to asynchronous hardware shutter triggers and linear focal lens zooms with auto-saving physical gallery injection (via `gal`).

---

## 🛠️ System Architecture & Data Path

```text
┌──────────────────────────────────────────────┐
│              LSM6DSOX IMU                   │
│  Raw Y-Axis Acceleration                    │
│  104 Hz / 10 ms Processing Loop             │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│           Arduino RP2040 Core               │
│  Localized Heuristic FSM                    │
│  Filters Muscle Recoil Ripples              │
└──────────────────────┬───────────────────────┘
                       │
                       │ BLE Notification
                       │ String Token
                       ▼
┌──────────────────────────────────────────────┐
│             Flutter Mobile Client           │
│  Tab-Aware Dispatcher                       │
│  Context Routing Block                      │
├──────────────────────────────────────────────┤
│ Tab 0 │ Telemetry Stream Console             │
│       │ Configuration Mute Floor             │
├──────────────────────────────────────────────┤
│ Tab 1 │ WebSocket Presentation Slide         │
│       │ Mirroring Core (Port 8080)           │
├──────────────────────────────────────────────┤
│ Tab 2 │ Custom Shutter & Lens Zoom           │
│       │ Viewfinder HUD Camera                │
└──────────────────────────────────────────────┘
```

---

## 📐 Firmware Mathematical Logic & Thresholds

The embedded state machine filters static earth gravity vector bias without trigonometric rotation math by executing a discrete first-order temporal differentiation:

$$\Delta y_t = y_t - y_{t-1} \approx a_{\text{dynamic},Y,t} - a_{\text{dynamic},Y,t-1}$$

The absolute $L_1\text{-norm}$ magnitude ($|\Delta y_t|$) maps movements directly into physical threshold brackets:
* **IDLE Noise Floor:** $|\Delta y_t| < 0.15g$ (Discarded)
* **Light Impact (TAP):** $0.15g \le |\Delta y_t| < 0.20g$
* **High Intensity (FIST):** $0.20g \le |\Delta y_t| < 0.40g$

### Multi-Stage Tiered Temporal Pillars
1. **Micro-Lockout Period (`globalLockoutEnd`):** Blinds the sensor array for $+180\text{ ms}$ post-tap or $+340\text{ ms}$ post-fist to absorb biological skin tissue shock ripples.
2. **Accumulation Window (`WINDOW_WAIT_MS`):** Keeps input lines open for $600\text{ ms}$ to log consecutive pulse frequencies, accurately separating single events from intentional double-actions.
3. **Macro-Lockout Recovery (`LOCKOUT_MS`):** Completely halts sampling registers for $450\text{ ms}$ instantly after transmitting a token over BLE to mute hand retraction movements.

---

## 🚀 Dependency Configuration & Setup

### 1. Flutter Mobile App (Android API 34)
To prevent cross-layer Transitive Dependency compilation crashes within the Kotlin DSL toolchain under modern security baselines, specific packages are pinned in the `pubspec.yaml` manifest:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: 1.31.15      # Zero-timeout MTU loops
  webview_flutter: 4.2.2          # Cleartext sandbox streaming
  camera: 0.10.6                  # CameraX API architecture lock
  gal: 2.1.2                      # Native asset filesystem injection
  file_picker: 8.3.6              # Synchronous file routing
  provider: 6.1.2                 # Tab reactive state tree manager
  shelf: 1.4.1                    # Local HTTP core engine
  shelf_web_socket: 1.0.4         # High-throughput frame streaming
```

### 2. Hardware Assembly List
* **Computational Chip:** Arduino Nano RP2040 Connect board
* **Sensing Array:** Onboard STMicroelectronics LSM6DSOX 6-Axis IMU
* **Power & Chassis:** 3.7V LiPo Battery cell, TP4056 charging management breakout, hardware slide power switch, mini DC-DC Boost Step-Up Converter (regulated to a stable flat 12V rail into the VIN pin), and custom 3D-printed Stacked Sandwich casing bound by a 20mm Nylon Velcro strap.

---

## 📊 Research Insight: Heuristic Rules vs. TinyML Edge Collapse

This project documents a transparent human-factors engineering evaluation. During laboratory validation, a complex **Edge Impulse TinyML Pipeline** utilizing combined **Spectral Analysis (FFT Length: 16)** and **Flatten (7 Global Statistics)** block preprocessing coupled with an 8-bit quantized neural network achieved an exceptional offline testing validation score of **85.42%**.

However, during live real-time continuous evaluation loops, the AI model **collapsed entirely to <10% execution reliability** due to two core factors:
1. **Streaming Window Mismatch:** The model is trained on neat, isolated 1-second static blocks. In reality, real-time data continuous streaming slices rapid micro-gestures (100–120ms) across random sliding splits, breaking pattern structures.
2. **Statistical Signal Dilution:** Averaging or transforming a fast 100ms impulse across a huge 1000ms window causes the gesture signature to dilute, making it look statistically identical to background IDLE background noise.

The C++ **Heuristic Threshold FSM** runs instantly per-sample with zero window latency, proving significantly more robust in continuous operations despite a raw 37.0% real-world accuracy boundary caused by natural muscle fatigue and biomechanical amplitude proximity overlap ($0.15g - 0.25g$).

---

## 📜 Acknowledgement
This research activity is supported through **RIIM Kompetisi funding** from the Indonesia Endowment Fund for Education Agency (LPDP), Ministry of Finance of the Republic of Indonesia and National Research and Innovation Agency of Indonesia (BRIN) according to contract number `47/IV/KS/02/2025` and `052/SAM4/PPM/2025`. Special thanks to **Telkom University** and the **University Center of Excellence for Intelligent Sensing-IoT (PUI-PT Intelligence Sensing IoT)**.
