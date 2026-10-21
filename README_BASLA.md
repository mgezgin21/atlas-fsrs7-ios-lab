# Atlas FSRS-7 — iOS GitHub Actions kabul deneyi (İZOLE)

**Tarih:** 21 Ekim 2026  
**Durum:** Kaynak ve statik CI kontrolleri hazır; GitHub üzerinde henüz ÇALIŞTIRILMADI.  
**Protokol:** FSRS-7 araştırma deneyi. Atlas'ın Flutter/Isar/SymEngine dosyaları bu ZIP'e alınmadı, değiştirilmez.

## Neyi biliyoruz?

- Windows Rust `cargo test --release`: **8/8 PASS** (kullanıcının raporu).
- Windows Dart → Rust DLL gerçek FFI: **PASS**.
- Android ARM64 derleme, Debug ve Release/AOT APK oluşturma: **PASS**.
- Android ARM64 fiziksel cihazda Debug + Release/AOT gerçek FFI: **PASS**.
- iOS: **HENÜZ TEST EDİLMEDİ**.

## Bu test ne yapacak?

Tek `macos-15` Apple Silicon runner üzerinde FSRS-7 kaynağını **tam commit SHA** ile alır; `aarch64-apple-ios` ve `aarch64-apple-ios-sim` Rust statik kütüphanelerini derler, C sembol/bağlantı sınamasını yapar, bağımsız Flutter uygulaması oluşturur, iOS Simulator Debug uygulamasına statik Rust kütüphanesini bağlar ve **Simulator içinde gerçek Dart FFI çağrısı** çalıştırır. Sonucu nonce ile eşleştirilmiş geçici uygulama sandbox dosyasından okur. Ayrıca **fiziksel iPhone ARM64 için unsigned Flutter Release derlemesi** yapar.

**Fiziksel iPhone testi bu CI'da yapılamaz**; cihaz kurulum, provisioning, TestFlight/gerçek iPhone kabulü ayrı bir testtir. Simulator PASS, gerçek iPhone PASS değildir.

## Nasıl çalıştırılır?

1. GitHub'da `atlas-fsrs7-ios-lab` adında bir **Private** repo aç. Boş depoda README oluşturma zorunluluğu yok.
2. Bu ZIP'in **içeriğini** repoya yükle. Ana dizinde `Cargo.toml`, `src/lib.rs`, `ios_probe/main.dart`, `scripts/ios/patch_runner_link.rb`, `tests/ios/ffi_link_probe.c` ve **`.github/workflows/atlas-fsrs7-ios-verification.yml`** yer almalı. GitHub Actions kaynak ZIP'i doğrudan çalıştırmaz: dosyalar repoda açılmış olmalı.
3. GitHub → **Actions** → **Atlas FSRS-7 iOS Native + Flutter FFI Acceptance** → **Run workflow**.
4. Tüm adımlar bitince Action çalışma bağlantısını veya başarısız adıma ait **logu** gönder. Tüm satırlar geçerse iOS Simulator FFI ve iPhone unsigned build kabulünü güncelleriz.

**Maliyet:** Private GitHub depolarındaki macOS Actions dakikaları planının kullanım kotasından düşebilir; CI'da gerekirse işlem uzayabilir. Süre/sayı garantisi verilmez.

## Beklenen kabul işaretleri

- `FSRS7_PINNED_SOURCE=PASS`
- `IOS_DEVICE_AND_SIM_ARM64_LIBS=PASS`
- `IOS_C_FFI_LINK_PROBE=PASS`
- `IOS_ISOLATED_XCODE_NATIVE_LINK_PATCH=PASS`
- `IOS_SIMULATOR_FLUTTER_DEBUG_LINK=PASS`
- `STATUS=PASS` ve doğru `NONCE` uygulama sandbox marker'ında
- `IOS_SIMULATOR_REAL_DART_STATIC_RUST_FFI=PASS`
- `IOS_IPHONE_ARM64_FLUTTER_RELEASE_LINK=PASS`

**Önemli ayrım:** `IOS_IPHONE_ARM64_FLUTTER_RELEASE_LINK=PASS` gerçek iPhone üzerinde çalıştı demek değildir. Bu yalnız unsigned Release build ve linker kabulüdür.

## Güvenlik ve sürüm

- FSRS çekirdek kaynağı SHA: `0a5737406a0c5c7a5259b144738cbe4a0b649d76`.
- Bu arşivin `src/lib.rs` ve `Cargo.toml` dosyaları Windows ve Android'de test edilmiş prototipteki **aynı baytlardır**; matematik ve C ABI değiştirilmemiştir.
- C ABI prototip: `engine=7`, `abi=1`, `parameters=34`, `Memory=12 bayt`, `Next=64 bayt`.
- iOS üzerinde `.a` statik bağlanır; Dart tarafında `DynamicLibrary.process()` kullanılır. Flutter iOS FFI için uygun model budur.
- iOS uygulaması yalnız kendi test sandbox'ında nonce/sonuç yazar; Atlas kullanıcısının veritabanına erişmez.
- Algoritma düzeyinde ilk/10 dakikalık hesaplar Windows ve Android'deki değerle `0.02 gün` tolerans dahilinde karşılaştırılır.
- CI çalıştırıcısı **kaynak aşamasında** YAML + Ruby sözdizimi açısından incelendi. Gerçek Apple/Xcode testi PASSED olarak işaretlenmedi.

## Olası CI hataları

- Xcode `force_load`/`OTHER_LDFLAGS`: iOS statik link problemi; log gerekir.
- iPhone simulator runtime yok: Apple runner image yükleme/başlatma gereksinimi; bu hata FSRS-7 matematiksel başarısızlığı değildir.
- Rust iOS build kaynak yetersizliği / timeout: `macos-15` M1 runner kapasitesi; derleme optimizasyonları zaten CI testine özel hafifletildi.
- Flutter `pub` veya CocoaPods bağımlılık sorunu: API ve Xcode ortam sürümü log üzerinden değerlendirilir.
- `STATUS=FAIL`: gerçek simulator FFI çalışma başarısızlığı, kodu ve native linker yapılandırmasını gözden geçirmek gerekir.

**Bu sonuçlar tamamlanmadan Atlas üretimine FSRS-7 etkinleştirilmez.** Sonrasında da gerçek iPhone ve Atlas entegrasyon/isarla kayıt, geçiş ve veri koruma fazları bekler.
