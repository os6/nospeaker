```text
────────────────────────  a90.com presents  ─────────────────────────

    _   __ ____      _____  ____   ______ ___     __ __  ______ ____
   / | / // __ \    / ___/ / __ \ / ____//   |   / //_/ / ____// __ \
  /  |/ // / / /    \__ \ / /_/ // __/  / /| |  / ,<   / __/  / /_/ /
 / /|  // /_/ /    ___/ // ____// /___ / ___ | / /| | / /___ / _, _/
/_/ |_/ \____/    /____//_/    /_____//_/  |_|/_/ |_|/_____//_/ |_|

─  haptic voice synthesis  ─────────────────────────────  trackpad  ─
```
**Tắt tiếng Mac đi. Trackpad của bạn vẫn sẽ nói.**

Trong trackpad của MacBook không có loa, chỉ có một mô-tơ haptic nhỏ gõ lên mặt kính để bạn cảm nhận
tiếng click. NO SPEAKER điều khiển mô-tơ đó tới 4.000 lần mỗi giây, đủ nhanh để tạo ra âm thanh nghe
được, và biến nó thành giọng nói. Nó nói, hát, rap, và trở thành một nhạc cụ dưới ngón tay bạn.

Chỉ một lệnh. Khoảng một phút rưỡi. Không dùng chiếc loa nào.

[Xem bản demo trên X](https://x.com/codycollier/status/2124505859883716918), nhớ bật tiếng.

## 01 / trước khi bắt đầu

```text
[ mute your mac ]        it still talks; that's the point
[ put it on a table ]    on your lap it's much quieter
[ hands off the glass ]  until it asks you to touch it
```
**Space** bỏ qua một phần. **q** hoặc **Ctrl-C** nhảy tới phần cuối.

## 02 / cách chạy

`[ one line ]`

```sh
curl -fsSL a90.com/nospeaker | sh
```
Tải bản phát hành mới nhất về `~/.local/bin/nospeaker` và bắt đầu buổi trình diễn. `a90.com/nospeaker`
trỏ tới [play.sh](play.sh) trong repo này, nên bạn có thể đọc trước xem nó chạy những gì.

`[ download ]`

Tải `nospeaker.zip` từ [bản phát hành mới nhất](https://github.com/os6/nospeaker/releases/latest),
giải nén và chạy `./nospeaker` trong Terminal. Đã ký bằng Developer ID và được Apple công chứng.

`[ from source ]`

Cần Xcode hoặc Command Line Tools (`xcode-select --install`). Biên dịch thành một chương trình duy nhất
cho cả Mac Apple Silicon và Intel. Nếu chỉ biên dịch bằng Command Line Tools, phần Intel cần macOS 13
trở lên.

```sh
git clone https://github.com/os6/nospeaker
cd nospeaker
./build.sh
./nospeaker
```
## 03 / chơi thử

```text
./nospeaker "hello there"            say anything
./nospeaker --voice Daniel "hello"   in another macOS voice
./nospeaker --sweep                  a rising tone, 100 Hz to 4 kHz

--dark                               white on black
--plain                              no visuals, plain text
--external                           play through an external Magic Trackpad
```
## 04 / yêu cầu

Một trackpad Force Touch (tích hợp sẵn trong MacBook từ 2015 trở đi, hoặc Magic Trackpad 2 trở lên),
và macOS 12 trở lên. Nếu không có trackpad Force Touch, chương trình sẽ báo và thoát.

```text
tested on

MacBook Pro (Mac17,10)         M5 Max   macOS 27.2.1   everything works
MacBook Pro (MacBookPro15,1)   Intel    macOS 15.7.4   works, built from source
```
Chưa kiểm chứng: Magic Trackpad, và các phiên bản macOS cũ hơn 15. MultitouchSupport là framework
riêng (private), nên các hệ thống cũ có thể thiếu những hàm mà chương trình dùng, và độ lớn âm thanh
cũng khác nhau giữa các trackpad. Nếu bạn thử trên một chiếc Mac khác, hãy mở issue kèm model máy,
phiên bản macOS của bạn và mô tả âm thanh nghe được.

## 05 / nguyên lý hoạt động

```text
say ──▶ formants ──▶ two tones ──▶ motor ──▶ glass
        per 10 ms    F1 + F2       haptics   sound
```
**Vì sao bạn nghe được.** Trackpad không có loa, nhưng mô-tơ làm mặt kính chuyển động. Được điều khiển
qua lại hàng trăm, hàng nghìn lần mỗi giây, mặt kính rung đủ nhanh để tạo ra âm thanh nghe được. Âm
thanh nhỏ vì mô-tơ vốn được chế tạo cho những cú gõ ngắn, không phải để phát tiếng.

**Mô-tơ.** `MultitouchSupport` là framework riêng mà macOS dùng cho trackpad. Hàm
`MTActuationCreateFromDictionary` của nó nhận một mô tả về một rung động — một danh sách các âm sine,
mỗi âm có tần số, cường độ và độ dài riêng — và `MTActuationActuate` phát mô tả đó lên mô-tơ. API
haptics công khai của Apple chỉ cung cấp ba kiểu gõ cố định.

**Dải tần.** Đo bằng chính micro của MacBook, mọi nửa cung (semitone) từ 98 Hz tới 3.951 Hz: âm thanh
lớn hơn một căn phòng yên tĩnh bao nhiêu, và bao nhiêu phần của âm thanh là chính nốt nhạc đó.

```text
│                                      ###
│                          #+#     +++#####        #
│                         +#+#+   .+++#####       .#
│              .       ++++#+#+   .+++#####    # #.# #
│   ++        +. . #..+++++#+#++++.+++#####+ #####.###          .#
│   +++#.     +...+#..+++++#+#++++.+++#####+ #####.####+        .#
│  ++++#...   +...+#..+++++#+#++++.+++#####+.#####.####+        .#
│ .++++#...++++...+#..+++++#+#++++.+++#####+.#####.####+  +#    .#
│..++++#...++++...+#..+++++#+#++++.+++#####+.#####.####+#.+#  .#.#
│..++++#...++++...+#..+++++#+#++++.+++#####+.#####.####+#.+#+..#.#
└─────────────────────────────────────────────────────────────────
      131         262         523         1047        2093    3951
   public notes stop at 600 Hz ─┘

across: every semitone, in Hz · up: loudness, +16 to +34 dB
# clean note   + fair   . mostly buzz
```
Âm thanh rõ từ khoảng 100 Hz tới 4 kHz, với vài điểm chết nơi mặt kính cộng hưởng. Những nốt lớn nhất
và trong nhất của nó nằm quanh 1 kHz, bao phủ phần quan trọng nhất của giọng nói.

**Giọng nói.** Giọng nói có sẵn của macOS đọc câu chữ vào bộ nhớ. Mỗi 10 ms, phương pháp dự đoán tuyến
tính (linear prediction) tìm ra hai cộng hưởng (formant) mạnh nhất của giọng, cùng độ lớn và cao độ của
nó. Mô-tơ phát hai cộng hưởng đó thành các âm, khởi động lại theo từng nhịp của cao độ, để chúng rè rè
như giọng nói thay vì huýt sáo. Các âm gió (s, f, t) trở thành những chùm âm cao ngắn. Hai cộng hưởng
thắng ba: trong thử nghiệm mù (blind test) chúng rõ hơn và lớn hơn, vì sức của mô-tơ bị chia thành ít
đường hơn.

Nghe như giọng rô-bốt, và dễ theo dõi hơn nhiều khi bạn được đọc cùng, đó là lý do chương trình gõ ra
từng dòng chữ trong lúc nó nói.

**Mã nguồn.** Một file Swift duy nhất, [nospeaker.swift](nospeaker.swift), không phụ thuộc thư viện nào.

## 06 / lưu ý

- **Có an toàn không?** Chương trình không bao giờ điều khiển mô-tơ vượt quá cường độ tối đa thông
  thường của nó. Vượt quá thì làm được và sẽ to hơn, nhưng driver bắt đầu bị khựng, nên nospeaker
  không làm vậy.
- MultitouchSupport là framework riêng và không có tài liệu, nên một bản cập nhật macOS có thể làm
  chương trình hỏng.

Tên các hàm của MultitouchSupport được học từ dự án mã nguồn mở Tactile. Mọi thứ còn lại đều được đo
đạc trên một chiếc MacBook.

```text
──────────────────────  thanks for listening  ───────────────────────
```
Được làm bởi [Cody Collier](https://x.com/codycollier) · [a90.com](https://a90.com) · [Giấy phép MIT](LICENSE)
