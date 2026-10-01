
# 🍳 PortableCook — Multi-Modal AI Cooking Companion

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![RevenueCat](https://img.shields.io/badge/RevenueCat-In--App%20Purchases-E75243)](https://www.revenuecat.com)
[![Google Play](https://img.shields.io/badge/Google%20Play-Live-brightgreen)](https://play.google.com/store/apps/details?id=com.portablecook.app)

> **Official Store Listing**: [Download on Google Play](https://play.google.com/store/apps/details?id=com.portablecook.app)  
> **Built for RevenueCat Shipaton 2026** | Targeting: **Influencer Award — Nutrition & Healthy Eating (Abbey’s Kitchen)** & **HAMM Award**

---

## 📌 Overview
Staring into a full fridge and feeling like there is nothing to eat leads to decision fatigue and unnecessary food waste. **PortableCook** transforms raw ingredients into culinary inspiration using multi-modal AI—generating delicious, satisfying meals without calorie counting or rigid meal plans.

---

## 🚀 Key Features
* **Smart Virtual Fridge**: Upload photos or videos of your pantry/fridge to generate meal ideas, grocery checklists, and perishable alerts.
* **AI Recipe Video Extraction**: Extract structured ingredients and step-by-step instructions from cooking video files or YouTube links.
* **Step-by-Step Cooking Visualizer**: Generate visual image and video walkthroughs of complex cooking techniques.
* **Cooking Event Calendar**: Schedule upcoming meals with background notification alerts powered by `flutter_local_notifications`.
* **RevenueCat Monetization**: Pro ($25/mo) and Premium ($35/mo) tiers with tiered video upload limits (15MB/60MB) and consumable analysis credit packs.

---

## 💳 Judge Reviewer Credentials & Promo Codes
* **Reviewer Account**: `reviewer@portablecook.app` / `Reviewer123!`
* **Google Play / RevenueCat Promo Codes**:
  * 👑 **Premium Subscription**: `PORTABLECOOKFREE`
  * ⚡ **10 Analysis Credit Pack**: `WF5XLES6A8RP5CY2ZURNKBJ`

---

## 🛠 Tech Stack & Architecture
* **Frontend**: Flutter / Dart with `cached_network_image`, `file_picker`, and timezone-aware local notifications
* **Monetization Engine**: RevenueCat SDK (`purchases_flutter`)
* **Backend API**: Python REST API on Azure App Services (`https://portablebook-cmeudedafkdgdxfc.eastus-01.azurewebsites.net`)
* **AI Processing**: Gemini 3 Flash multi-modal video/image analysis endpoints

---

## 📂 Project Structure
```text
portablecook/
├── android/               # Native Android configuration & notifications
├── ios/                   # Native iOS configuration
├── lib/
│   ├── main.dart          # Entry point, RevenueCat config, notification handlers
│   ├── models/            # CookingEvent, UserSession, UserTier
│   ├── services/          # ApiService (Fridge analysis, video extraction, Azure backend)
│   └── screens/           # HomeScreen, VirtualFridgeScreen, GenerateScreen, AnalyzeScreen, UpgradeScreen
├── azure_por/             # Azure backend services
│   ├── app.py             # Flask multi-modal API
│   ├── users.db           # SQLite database
│   └── requirements.txt   # Dependencies
└── pubspec.yaml           # Flutter dependencies
```

---

## ⚙️ Getting Started
```bash
git clone https://github.com/Jerryblessed/portablecook.git
cd portablecook
flutter pub get
flutter run
```

---

## 📄 License
This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
