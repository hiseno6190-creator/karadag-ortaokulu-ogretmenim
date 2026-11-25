# Karadağ Ortaokulu Excel çizelgesi – teknik inceleme

Kaynak dosya: `öğretmen ders programı.xlsx`  
Çalışma sayfası: `Sayfa1`  
Boyut: 1.434 satır × 10 sütun  
Dosya tarihi hücresi: `25/11/2026`

## Tespit edilen yapı

- Her öğretmen kaydı, A sütununda `T.C.` bulunan satırla başlıyor.
- Öğretmen adı, başlangıç satırından 5 satır aşağıda C sütununda.
- Sınıf öğretmenliği bilgisi, başlangıç satırından 4 satır aşağıda H sütununda.
- Haftalık ders çizelgesi, başlangıç satırından 9–13 satır aşağıda; A sütununda gün, B–H sütunlarında 1–7. ders bulunuyor.
- Ders hücresi iki satırlı metin: ilk satır sınıf etiketi (ör. `6/E`), ikinci satır ders kodu (ör. `BTY6`).
- Haftalık toplam saat, başlangıç satırından 14 satır aşağıda C sütununda.
- Ders adı eşleştirmesi, başlangıç satırından 16. satırdan itibaren gelen detay tablosunda F sütunundaki ders kodu ve H sütunundaki ders adıyla yapılıyor.
- Bir sonraki `T.C.` satırı mevcut öğretmen bloğunun sonunu belirliyor. Bu nedenle sabit öğretmen sayısı veya sabit blok satır aralığı kullanılmıyor.

## Kaynak dosyadan doğrulanan sayımlar

- 47 öğretmen bloğu ve 47 benzersiz öğretmen adı.
- Her öğretmen için 5 hafta içi gün satırı.
- 7 ders sütunu.
- Haftalık çizelgelerde toplam 1.004 dolu ders hücresi.
- Ders ayrıntı tablolarında 636 satır.
- 28 farklı sınıf etiketi ve 56 farklı ders kodu.
- Her öğretmenin beyan ettiği toplam ders saati, haftalık çizelgesindeki dolu hücre sayısıyla eşleşiyor.
- Haftalık çizelgede kullanılan ders kodlarının tamamı ilgili öğretmenin detay tablosunda karşılık buluyor.

## Saat başlıkları hakkında

Excel başlığındaki ilk ders saati hücresi bozuk/eksik biçimlenmiş görünüyor (`8:30 : 0`). Diğer başlıklar Excel'de 09:30–10:10, 10:20–11:00, 11:10–11:50, 12:30–13:10, 13:20–14:00 ve 14:10–14:50 olarak yazılı. Uygulama, önceki kararlaştırılmış varsayılan zil saatlerini korur; Excel'den gelen ders atamalarını zil saatleriyle karıştırmaz. Zil saatleri ayrı ayarlanır.

## İçe aktarma davranışı

1. Kullanıcı `.xlsx` veya `.pdf` dosyası seçer.
2. Excel ayrıştırıcısı tüm çalışma sayfalarını tarar ve `T.C.` satırlarından öğretmen bloklarını dinamik olarak bulur.
3. Ders hücreleri gün + ders saati + sınıf + ders kodu şeklinde kaydedilir.
4. Ders kodları, öğretmenin detay tablosundaki ders adlarıyla eşleştirilir.
5. Öğretmen toplam saati ile çizelgedeki dolu hücre sayısı karşılaştırılır; fark varsa önizlemede uyarı gösterilir.
6. Kullanıcı onaylarsa mevcut programın yedeği alınır ve yeni program yerel cihaza kaydedilir.

## Doğrulama sınırı

Bu sayımlar kaynak Excel dosyası üzerinde bağımsız olarak kontrol edildi. Flutter uygulamasının Android derlemesi ve telefonda gerçek dosya içe aktarma testi henüz yapılmadı; bu nedenle ilk APK testinden sonra gerçek cihaz doğrulaması gereklidir.
