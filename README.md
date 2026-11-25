# Karadağ Ortaokulu – Öğretmenim (Flutter Android)

Çevrimdışı çalışan öğretmen ders programı uygulaması. Android APK, GitHub Actions üzerinden üretilebilir.

## Özellikler
- Öğretmen adına göre arama ve seçilen öğretmeni cihazda sabitleme
- Pazartesi–Cuma ders çizelgesi ve düzenlenebilir ders saatleri
- Excel (.xlsx) ve PDF program aktarımı
- Program yedekleme ve geri yükleme
- Ders başlamadan 1 dakika önce **“Ders başlıyor”** bildirimi
- Ders bitmeden 1 dakika önce **“Ders bitiyor, teneffüs başlıyor”** bildirimi
- İsteğe bağlı kalıcı okul günü bildirimi: ilk dersten 30 dakika önce görünür, son dersin bitiminden 10 dakika sonra otomatik kapanır
- Kalıcı bildirim kilit ekranında ve bildirim panelinde görünür; günün motivasyon mesajını içerir
- Bildirim planları cihaz yeniden başlatıldığında yeniden kurulur

## Kalıcı bildirim davranışı
Hakkında ekranındaki bildirim anahtarı açıldığında Android bildirim izni istenir. Pazartesi–Cuma günleri için ilk ders başlangıcından 30 dakika önce bir Android foreground service başlatılır. Bu servis, devamlı bildirim (`ongoing`) gösterir; bildirim kilit ekranında görünür ve kullanıcı tarafından normal şekilde kaydırılarak kapatılamaz. Son dersin bitişinden 10 dakika sonra planlanan alarm servisi durdurur ve kalıcı bildirimi kaldırır. Bildirim metni haftanın gününe göre değişen kısa motivasyon cümlelerinden oluşur.

Kalıcı bildirim saatleri ders saatleri ekranındaki ilk dersin başlangıcı ve son dersin bitişi kullanılarak hesaplanır. Ders saatleri değiştirildiğinde açık bildirim tercihi varsa planlar yenilenir. Ana ekran widget/bileşeni bu sürümden çıkarılmıştır.

## Derleme
GitHub Actions iş akışı `.github/workflows/android-apk.yml` dosyasındadır. Flutter stable ile Android platform dosyaları üretilir, `.github/scripts/configure_android.py` Android bildirim izinlerini, Kotlin foreground service/alarm sınıflarını ve küçük bildirim ikonunu ekler; ardından `flutter analyze` ve release APK derlemesi çalışır.

Bu geliştirme oturumunda Flutter SDK bulunmadığı için APK yerel olarak derlenemedi. Gerçek cihazda, özellikle Android 13/14+, pil optimizasyonu ve üretici arka plan kısıtlamaları altında test edilmelidir. Alarm API'si pil tasarrufu koşullarında birkaç dakika gecikebilir; kesin dakika garantisi verilmez. Kullanıcı Android ayarlarından uygulama bildirimlerini kapatırsa bildirimler görünmez.

## Excel ayrıştırıcı notu
Excel ayrıştırıcısı çalışma kitabındaki `T.C.` satırlarını öğretmen blok başlangıcı olarak algılar; öğretmen çizelgelerini ve ders listesini blok içi konumlara göre okur. Excel dosyasının biçimi değişirse ayrıştırıcı güncellenmelidir. PDF içe aktarma özelliği korunmuştur; Syncfusion PDF paketinin lisans koşulları dağıtımdan önce kontrol edilmelidir.


## Gelişmiş kalıcı bildirim

Kalıcı Android bildirimi, ilk dersin başlamasından 30 dakika önce açılır ve son dersin bitiminden 10 dakika sonra kapanır. Okul günü boyunca bildirim yaklaşık dakikada bir yenilenerek seçili/sabitlenmiş öğretmenin o anki dersini, dersin adını ve sınıfını; teneffüste ise sıradaki dersi ve derse kalan dakikayı gösterir. Motivasyon cümlesi de genişletilmiş bildirim içeriğinde yer alır. Öğretmen sabitlendiğinde veya program/saatler güncellendiğinde bildirim verisi yeniden senkronize edilir. Android kilit ekranında görünüm, cihazın bildirim ve kilit ekranı gizlilik ayarlarına bağlıdır.
