# WakeUp ⏰ - The Relentless Alarm App

**WakeUp** is a robust Flutter application designed to guarantee the user gets out of bed. Unlike standard alarms, WakeUp enforces physical activity or specific tasks to dismiss the alert. It integrates hardware sensors, camera input, and precise background scheduling to create an "unstoppable" wake-up experience.

This project demonstrates the integration of native device features within the Flutter ecosystem, handling complex lifecycle states and hardware sensors.

---

## 📱 Core Features

* **🛡️ Secure Alarm State:** The alarm continues to ring even if the app is minimized, the screen is locked, or the user attempts to lower the volume.
* **🏃 Motion Detection Algorithm:** Utilizes the device's accelerometer to track G-force vectors. The user must vigorously shake or move the device for a set duration to prove they are awake.
* **📷 QR Code Verification:** Implements a computer vision module that requires the user to walk to a different room and scan a specific QR code to stop the alarm.
* **🔄 Persistence & State Management:** Supports recurring daily alarms and saves user preferences via local storage, ensuring reliability even after app restarts.
* **🔔 Sticky Notifications:** Deploys high-priority foreground notifications to maintain the alarm service active.

---

## 🛠️ Tech Stack & Engineering

Built with **Flutter**, targeting **Android** (API Level 21+).

### Key Libraries & Architecture
* **Background Execution:** `alarm` package for precise scheduling and `wakelock_plus` to manage screen power states.
* **Hardware Integration:**
    * `sensors_plus`: Real-time accelerometer data stream processing for motion tracking.
    * `mobile_scanner`: Efficient QR code scanning using CameraX / AVFoundation.
    * `vibration`: Custom haptic feedback patterns.
* **Audio Engine:** `audioplayers` for looping audio assets and `flutter_volume_controller` to enforce maximum system volume during the alarm state.
* **Localization:** `flutter_localizations` ensuring correct UI rendering (e.g., Cupertino date pickers) across different region settings.

### Technical Highlights

#### 1. Motion Detection Logic
The app listens to the accelerometer stream (`accelerometerEvents`) and calculates the magnitude of the 3D vector to filter out noise and detect significant movement.

    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      // Calculate the magnitude of the 3D G-force vector
      // x, y, z represent the acceleration on each axis
      double force = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      // Threshold logic to detect vigorous movement (ignoring minor shakes)
      if (force > 11.0 || force < 8.5) {
        _resetInactivityTimer();
      }
    });

#### 2. Android Lifecycle & Optimization
To prevent the Android OS from killing the alarm process to save battery, the app implements:
* **Wake Locks:** Acquires a `PARTIAL_WAKE_LOCK` to keep the CPU running and screen active.
* **Foreground Service:** Runs the alarm with a visible notification, signaling high priority to the Android scheduler.
* **Native Permissions:** Optimized `AndroidManifest.xml` to handle `SYSTEM_ALERT_WINDOW` (drawing over other apps) and `SCHEDULE_EXACT_ALARM`.

---

## 📸 Screenshots

| Home (Idle) | Alarm Scheduled | Alarm Ringing | Motion Challenge |
|:---:|:---:|:---:|:---:|
| <img src="assets/screenshots/home.png" width="200"> | <img src="assets/screenshots/scheduled.png" width="200"> | <img src="assets/screenshots/ringing.png" width="200"> | <img src="assets/screenshots/motion.png" width="200"> |

*(Note: Screenshots are stored in the `assets/screenshots` directory)*

---

## 🚀 Getting Started

To run this project locally, you will need a physical Android device (emulators often do not support accelerometer data correctly).

### Prerequisites
* Flutter SDK (3.22.0 or higher)
* Dart SDK (3.0.0 or higher)
* Android Studio / VS Code

### Installation

1. Clone the repository:
    git clone https://github.com/your-username/wakeup.git
    cd wakeup

2. Install dependencies:
    flutter pub get

3. Run the app:
    flutter run --release

*Note: For the alarm to function correctly on OEM versions of Android (Samsung, Xiaomi, etc.), ensure battery optimization is disabled for the app settings.*

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.