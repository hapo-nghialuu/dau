# Kết quả kiểm thử gõ tiếng Việt — `dau-core`

> **Ngày:** 2026-07-23  
> **Nhánh:** `fix/linux-ship-profiles-frontend-ibus`  
> **Phạm vi:** engine Rust (`dau-core`) — Telex + VNI. **Không** thay bằng gõ tay Terminal (đã verify riêng: GNOME Terminal + `frontend:ibus=preedit`).  
> **Cách chạy lại:**
>
> ```bash
> cd core
> cargo test --test full_vietnamese_corpus -- --nocapture
> # inventory mở rộng (probe ngoài crate): xem lịch sử session / core/target/
> ```

## Tóm tắt

| Bộ | PASS | FAIL | Ghi chú |
|----|------|------|---------|
| Telex (inventory ~407 mục) | **373** | **34** | PASS = có ≥1 chuỗi phím đúng |
| VNI (nguyên âm + từ cốt lõi) | **101** | **0** | |
| Corpus unit (`full_vietnamese_corpus`) | **140** | **6** | case cố định; một số FAIL do sequence UniKey |

### Ý nghĩa

- **Gõ được:** `Engine::process_char` từng phím → `composing()` **trùng** từ kỳ vọng.
- **FAIL:** sequence đã thử **không** ra đúng từ (thiếu quy tắc đặt dấu / thứ tự phím). Có thể vẫn gõ được bằng sequence khác chưa liệt kê.
- **Không claim** cover 100% từ điển tiếng Việt.

### 6 FAIL corpus cố định (Telex/VNI)

| Gõ | Kỳ vọng | Thực tế | Sequence đúng hơn (probe) |
|----|---------|---------|---------------------------|
| `viecj` | việc | viẹc | `vieecj` / `vieejc` |
| `thaangs` | tháng | thấng | `thangs` |
| `moowis` | mới | môứi | `mowis` |
| `cuwx` | cũ | cữ | `cux` (Telex) / `cu4` (VNI) |
| `ddocs` | đọc | đóc | `ddojc` / `ddocj` |
| VNI `cu74` | cũ | cữ | `cu4` |

---

Mỗi dòng: engine nhận chuỗi phím, so `composing()` với từ kỳ vọng.
Telex: thử nhiều sequence; PASS nếu **một** sequence đúng.

**Telex:** 373 PASS / 34 FAIL  
**VNI:** 101 PASS / 0 FAIL

## Telex — GÕ ĐƯỢC

| Từ | Cách gõ | Thực tế |
|----|---------|--------|
| a | `a` | a |
| anh | `anh` | anh |
| ba | `ba` | ba |
| bay | `bay` | bay |
| bia | `bia` | bia |
| biết | `bieest` | biết |
| biển | `bieern` | biển |
| biệt | `bieejt` | biệt |
| buồn | `buoofn` | buồn |
| buổi | `buoori` | buổi |
| bà | `baf` | bà |
| bàn | `bafn` | bàn |
| bác | `bacs` | bác |
| bán | `bans` | bán |
| bánh | `basnh` | bánh |
| bên | `been` | bên |
| bình | `bifnh` | bình |
| bò | `bof` | bò |
| bún | `buns` | bún |
| bước | `buwowcs` | bước |
| bại | `baij` | bại |
| bạn | `banj` | bạn |
| bản | `barn` | bản |
| bảy | `bayr` | bảy |
| bắt | `bawst` | bắt |
| bếp | `beesp` | bếp |
| bệnh | `beejnh` | bệnh |
| bố | `boos` | bố |
| bốn | `boosn` | bốn |
| cao | `cao` | cao |
| cay | `cay` | cay |
| chiều | `chieefu` | chiều |
| cho | `cho` | cho |
| chua | `chua` | chua |
| chào | `chaof` | chào |
| cháo | `chaos` | cháo |
| chí | `chis` | chí |
| chín | `chisn` | chín |
| chị | `chij` | chị |
| chờ | `chowf` | chờ |
| chợ | `chowj` | chợ |
| con | `con` | con |
| cà | `caf` | cà |
| cá | `cas` | cá |
| các | `cacs` | các |
| cái | `cais` | cái |
| cây | `caay` | cây |
| có | `cos` | có |
| cô | `coo` | cô |
| công | `coong` | công |
| cũ | `cux` | cũ |
| cơm | `cowm` | cơm |
| cả | `car` | cả |
| cần | `caafn` | cần |
| cố | `coos` | cố |
| củ | `cur` | củ |
| của | `cuar` | của |
| cửa | `cuwra` | cửa |
| dài | `daif` | dài |
| dưới | `duwowis` | dưới |
| dạy | `dayj` | dạy |
| dụng | `dungj` | dụng |
| dữ | `duwx` | dữ |
| e | `e` | e |
| em | `em` | em |
| file | `file` | file |
| ghế | `ghees` | ghế |
| giày | `giayf` | giày |
| giây | `giaay` | giây |
| giường | `giuwowngf` | giường |
| giỏi | `gioir` | giỏi |
| giờ | `giowf` | giờ |
| giữa | `giuwax` | giữa |
| gà | `gaf` | gà |
| gái | `gais` | gái |
| gần | `gaafn` | gần |
| gầy | `gaayf` | gầy |
| gắng | `gawsng` | gắng |
| hai | `hai` | hai |
| heo | `heo` | heo |
| hiểm | `hieerm` | hiểm |
| hiểu | `hieeru` | hiểu |
| hoa | `hoa` | hoa |
| hoà | `hoaf` | hoà |
| hoá | `hoas` | hoá |
| hoặc | `hoawjc` | hoặc |
| huế | `huees` | huế |
| hà | `haf` | hà |
| hàn | `hafn` | hàn |
| hôi | `hooi` | hôi |
| hôm | `hoom` | hôm |
| hẹp | `hepj` | hẹp |
| hết | `heest` | hết |
| học | `hocj` | học |
| hồ | `hoof` | hồ |
| i | `i` | i |
| internet | `internet` | internet |
| khoắn | `khoawns` | khoắn |
| khoẻ | `khoer` | khoẻ |
| khó | `khos` | khó |
| không | `khoong` | không |
| kiểm | `kieerm` | kiểm |
| lan | `lan` | lan |
| liệu | `lieeju` | liệu |
| làm | `lafm` | làm |
| làng | `lafng` | làng |
| lào | `laof` | lào |
| lá | `las` | lá |
| lên | `leen` | lên |
| lúa | `luas` | lúa |
| lương | `luowng` | lương |
| lạnh | `lanhj` | lạnh |
| lỗi | `looxi` | lỗi |
| lớn | `lowns` | lớn |
| lớp | `lowsp` | lớp |
| mai | `mai` | mai |
| minh | `minh` | minh |
| miến | `mieesn` | miến |
| mua | `mua` | mua |
| muốn | `muoons` | muốn |
| muộn | `muoojn` | muộn |
| màn | `mafn` | màn |
| mát | `mats` | mát |
| máy | `mays` | máy |
| mì | `mif` | mì |
| mười | `muowif` | mười |
| mạng | `mangj` | mạng |
| mạnh | `manhj` | mạnh |
| mất | `maast` | mất |
| mắn | `mawns` | mắn |
| mặn | `mawnj` | mặn |
| mẹ | `mej` | mẹ |
| mềm | `meefm` | mềm |
| mỗi | `mooxi` | mỗi |
| một | `mootj` | một |
| mới | `mowis` | mới |
| mở | `mowr` | mở |
| mục | `mujc` | mục |
| nam | `nam` | nam |
| nay | `nay` | nay |
| nga | `nga` | nga |
| nghe | `nghe` | nghe |
| ngoài | `ngoaif` | ngoài |
| ngày | `ngayf` | ngày |
| người | `nguoiwf` | người |
| ngắn | `ngawns` | ngắn |
| ngọt | `ngojt` | ngọt |
| nhanh | `nhanh` | nhanh |
| nhiều | `nhieefu` | nhiều |
| nhà | `nhaf` | nhà |
| nhìn | `nhinf` | nhìn |
| như | `nhuw` | như |
| nhưng | `nhuwng` | nhưng |
| nhớ | `nhowrs` | nhớ |
| những | `nhuwngx` | những |
| này | `nafy` | này |
| nên | `neen` | nên |
| nói | `nois` | nói |
| nông | `noong` | nông |
| núi | `nuis` | núi |
| năm | `nawm` | năm |
| nước | `nuowsc` | nước |
| nẵng | `nawxng` | nẵng |
| nếu | `neesu` | nếu |
| nội | `nooij` | nội |
| o | `o` | o |
| pháp | `phaps` | pháp |
| phê | `phee` | phê |
| phím | `phims` | phím |
| phút | `phust` | phút |
| phải | `phair` | phải |
| phần | `phaafn` | phần |
| phố | `phoos` | phố |
| phở | `phowr` | phở |
| phức | `phuwsc` | phức |
| qua | `qua` | qua |
| quên | `queen` | quên |
| quần | `quaafn` | quần |
| quắm | `quawms` | quắm |
| quế | `quees` | quế |
| quốc | `quoocs` | quốc |
| ra | `ra` | ra |
| rau | `rau` | rau |
| rượu | `ruwowju` | rượu |
| rẻ | `rer` | rẻ |
| rồi | `rooif` | rồi |
| rộng | `roojng` | rộng |
| rủi | `ruir` | rủi |
| rừng | `ruwfng` | rừng |
| sai | `sai` | sai |
| sinh | `sinh` | sinh |
| siêu | `sieeu` | siêu |
| sáng | `sasng` | sáng |
| sáu | `saus` | sáu |
| sông | `soong` | sông |
| sạch | `sachj` | sạch |
| sẽ | `sex` | sẽ |
| sớm | `sowsm` | sớm |
| sợ | `sowj` | sợ |
| sữa | `suwax` | sữa |
| thiết | `thieest` | thiết |
| thiếu | `thieesu` | thiếu |
| thuế | `thuees` | thuế |
| thuốc | `thuoosc` | thuốc |
| thuỷ | `thuyr` | thuỷ |
| thành | `thafnh` | thành |
| thái | `thais` | thái |
| tháng | `thangs` | tháng |
| thì | `thif` | thì |
| thích | `thichs` | thích |
| thôn | `thoon` | thôn |
| thơ | `thow` | thơ |
| thơm | `thowm` | thơm |
| thư | `thuw` | thư |
| thấp | `thaaps` | thấp |
| thấy | `thaays` | thấy |
| thầy | `thaayf` | thầy |
| thế | `thees` | thế |
| thị | `thij` | thị |
| thịt | `thijt` | thịt |
| tiếng | `tieengs` | tiếng |
| tiền | `tieefn` | tiền |
| toà | `toaf` | toà |
| toàn | `toafn` | toàn |
| toán | `toans` | toán |
| tra | `tra` | tra |
| trai | `trai` | trai |
| triệu | `trieeju` | triệu |
| trong | `trong` | trong |
| trung | `trung` | trung |
| trà | `traf` | trà |
| trên | `treen` | trên |
| trăm | `trawm` | trăm |
| trường | `truowngf` | trường |
| trọng | `trojng` | trọng |
| trứng | `truwsng` | trứng |
| tuân | `tuaan` | tuân |
| tuần | `tuaafn` | tuần |
| tàu | `tauf` | tàu |
| tám | `tams` | tám |
| tìm | `tifm` | tìm |
| tính | `tinhs` | tính |
| tô | `too` | tô |
| tôi | `tooi` | tôi |
| túi | `tuis` | túi |
| tường | `tuwowngf` | tường |
| tạm | `tajm` | tạm |
| tạp | `tajp` | tạp |
| tập | `taajp` | tập |
| tối | `toois` | tối |
| tốt | `toots` | tốt |
| tủ | `tur` | tủ |
| từ | `tuwf` | từ |
| tỷ | `tyr` | tỷ |
| u | `u` | u |
| uôn | `uoon` | uôn |
| viên | `vieen` | viên |
| viết | `vieets` | viết |
| việc | `vieecj` | việc |
| viện | `vieejn` | viện |
| Việt | `Vieejt` | Việt |
| việt | `vieejt` | việt |
| vui | `vui` | vui |
| và | `vaf` | và |
| vài | `vaif` | vài |
| vào | `vaof` | vào |
| vì | `vif` | vì |
| văn | `vawn` | văn |
| về | `veef` | về |
| với | `vowis` | với |
| xa | `xa` | xa |
| xe | `xe` | xe |
| xin | `xin` | xin |
| xinh | `xinh` | xinh |
| xong | `xong` | xong |
| xuống | `xuoosng` | xuống |
| xấu | `xauas` | xấu |
| y | `y` | y |
| yêu | `yeeu` | yêu |
| yếu | `yeesu` | yếu |
| à | `af` | à |
| á | `as` | á |
| áo | `aos` | áo |
| â | `aa` | â |
| ã | `ax` | ã |
| è | `ef` | è |
| é | `es` | é |
| ê | `ee` | ê |
| ì | `if` | ì |
| í | `is` | í |
| ít | `ist` | ít |
| ò | `of` | ò |
| ó | `os` | ó |
| ô | `oo` | ô |
| ông | `oong` | ông |
| õ | `ox` | õ |
| ù | `uf` | ù |
| ú | `us` | ú |
| úc | `usc` | úc |
| ý | `ys` | ý |
| ă | `aw` | ă |
| đ | `dd` | đ |
| đang | `ddang` | đang |
| đau | `ddau` | đau |
| đi | `ddi` | đi |
| điểm | `ddieerm` | điểm |
| đà | `ddaf` | đà |
| đã | `ddax` | đã |
| đêm | `ddeem` | đêm |
| đúng | `ddungs` | đúng |
| đơn | `ddown` | đơn |
| đường | `dduwowngf` | đường |
| được | `dduwowcj` | được |
| đầy | `ddaayf` | đầy |
| đắng | `ddawsng` | đắng |
| đắt | `ddawst` | đắt |
| đẹp | `ddepj` | đẹp |
| đến | `ddeens` | đến |
| để | `ddeer` | để |
| đọc | `ddojc` | đọc |
| đức | `dduwcs` | đức |
| ĩ | `ix` | ĩ |
| ũ | `ux` | ũ |
| ơ | `ow` | ơ |
| ơn | `own` | ơn |
| ư | `uw` | ư |
| ạ | `aj` | ạ |
| ả | `ar` | ả |
| ấ | `aas` | ấ |
| ấm | `aams` | ấm |
| ầ | `aaf` | ầ |
| ẩ | `aar` | ẩ |
| ẫ | `aax` | ẫ |
| ậ | `aaj` | ậ |
| ắ | `aws` | ắ |
| ằ | `awf` | ằ |
| ẳ | `awr` | ẳ |
| ẵ | `awx` | ẵ |
| ặ | `awj` | ặ |
| ẹ | `ej` | ẹ |
| ẻ | `er` | ẻ |
| ẽ | `ex` | ẽ |
| ế | `ees` | ế |
| ề | `eef` | ề |
| ể | `eer` | ể |
| ễ | `eex` | ễ |
| ệ | `eej` | ệ |
| ỉ | `ir` | ỉ |
| ị | `ij` | ị |
| ọ | `oj` | ọ |
| ỏ | `or` | ỏ |
| ố | `oos` | ố |
| ồ | `oof` | ồ |
| ổ | `oor` | ổ |
| ỗ | `oox` | ỗ |
| ộ | `ooj` | ộ |
| ớ | `ows` | ớ |
| ờ | `owf` | ờ |
| ở | `owr` | ở |
| ỡ | `owx` | ỡ |
| ợ | `owj` | ợ |
| ụ | `uj` | ụ |
| ủ | `ur` | ủ |
| ứ | `uws` | ứ |
| ứng | `uwngs` | ứng |
| ừ | `uwf` | ừ |
| ử | `uwr` | ử |
| ữ | `uwx` | ữ |
| ự | `uwj` | ự |
| ỳ | `yf` | ỳ |
| ỵ | `yj` | ỵ |
| ỷ | `yr` | ỷ |
| ỹ | `yx` | ỹ |

## Telex — CHƯA gõ được (hết sequence đã thử)

| Từ | Seq cuối | Thực tế |
|----|----------|--------|
| bài | `bais` | bái |
| béo | `beof` | bèo |
| bẩn | `barn` | bản |
| chưa | `chuawa` | chua |
| chậm | `chajm` | chạm |
| cảm | `cams` | cám |
| dễ | `deer` | dể |
| giàu | `giaafu` | giầu |
| giá | `gias` | gía |
| giả | `giar` | gỉa |
| giản | `giarn` | gỉan |
| hình | `hinhs` | hính |
| hải | `hais` | hái |
| kém | `keems` | kếm |
| mũ | `mur` | mủ |
| mọi | `mois` | mói |
| mỹ | `myr` | mỷ |
| nghèo | `ngheefo` | nghềo |
| nghìn | `nghisn` | nghín |
| nhật | `nhajt` | nhạt |
| nhỏ | `nhowr` | nhở |
| nóng | `noosng` | nống |
| phòng | `phoofng` | phồng |
| quả | `quar` | qủa |
| sĩ | `sir` | sỉ |
| thuyền | `thuyeen` | thuyên |
| thất | `thast` | thát |
| thật | `thajt` | thạt |
| thừa | `thuwa` | thưa |
| tài | `tais` | tái |
| tại | `tais` | tái |
| đóng | `ddoosng` | đống |
| đủ | `dur` | dủ |
| ốm | `oms` | óm |

## VNI — GÕ ĐƯỢC

| Từ | Cách gõ | Thực tế |
|----|---------|--------|
| a | `a` | a |
| bước | `bu7o7c1` | bước |
| bạn | `ban5` | bạn |
| chào | `chao2` | chào |
| các | `cac1` | các |
| cũ | `cu4` | cũ |
| của | `cua3` | của |
| e | `e` | e |
| Hoà | `Hoa2` | Hoà |
| hoà | `hoa2` | hoà |
| học | `hoc5` | học |
| i | `i` | i |
| khoẻ | `khoe3` | khoẻ |
| không | `kho6ng` | không |
| làm | `lam2` | làm |
| mới | `mo7i1` | mới |
| người | `nguoi72` | người |
| người | `nguoi72` | người |
| này | `nay2` | này |
| năm | `na8m` | năm |
| nước | `nu7o7c1` | nước |
| o | `o` | o |
| phải | `phai3` | phải |
| thuỷ | `thuy3` | thuỷ |
| tháng | `thang1` | tháng |
| thế | `the61` | thế |
| tiếng | `tie6ng1` | tiếng |
| toán | `toan1` | toán |
| u | `u` | u |
| việc | `vie6c5` | việc |
| việt | `vie6t5` | việt |
| y | `y` | y |
| à | `a2` | à |
| á | `a1` | á |
| â | `a6` | â |
| ã | `a4` | ã |
| è | `e2` | è |
| é | `e1` | é |
| ê | `e6` | ê |
| ì | `i2` | ì |
| í | `i1` | í |
| ò | `o2` | ò |
| ó | `o1` | ó |
| ô | `o6` | ô |
| õ | `o4` | õ |
| ù | `u2` | ù |
| ú | `u1` | ú |
| ý | `y1` | ý |
| ă | `a8` | ă |
| đ | `d9` | đ |
| được | `d9u7o7c5` | được |
| đẹp | `d9ep5` | đẹp |
| ĩ | `i4` | ĩ |
| ũ | `u4` | ũ |
| ơ | `o7` | ơ |
| ư | `u7` | ư |
| ạ | `a5` | ạ |
| ả | `a3` | ả |
| ấ | `a61` | ấ |
| ầ | `a62` | ầ |
| ẩ | `a63` | ẩ |
| ẫ | `a64` | ẫ |
| ậ | `a65` | ậ |
| ắ | `a81` | ắ |
| ằ | `a82` | ằ |
| ẳ | `a83` | ẳ |
| ẵ | `a84` | ẵ |
| ặ | `a85` | ặ |
| ẹ | `e5` | ẹ |
| ẻ | `e3` | ẻ |
| ẽ | `e4` | ẽ |
| ế | `e61` | ế |
| ề | `e62` | ề |
| ể | `e63` | ể |
| ễ | `e64` | ễ |
| ệ | `e65` | ệ |
| ỉ | `i3` | ỉ |
| ị | `i5` | ị |
| ọ | `o5` | ọ |
| ỏ | `o3` | ỏ |
| ố | `o61` | ố |
| ồ | `o62` | ồ |
| ổ | `o63` | ổ |
| ỗ | `o64` | ỗ |
| ộ | `o65` | ộ |
| ớ | `o71` | ớ |
| ờ | `o72` | ờ |
| ở | `o73` | ở |
| ỡ | `o74` | ỡ |
| ợ | `o75` | ợ |
| ụ | `u5` | ụ |
| ủ | `u3` | ủ |
| ứ | `u71` | ứ |
| ừ | `u72` | ừ |
| ử | `u73` | ử |
| ữ | `u74` | ữ |
| ự | `u75` | ự |
| ỳ | `y2` | ỳ |
| ỵ | `y5` | ỵ |
| ỷ | `y3` | ỷ |
| ỹ | `y4` | ỹ |

## VNI — FAIL

| Từ | Cách gõ | Thực tế |
|----|---------|--------|

