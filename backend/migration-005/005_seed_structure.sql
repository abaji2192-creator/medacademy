-- 005 seed: data.js dagi mavjud modul/dars tuzilmasi va akademiyalar (yangi kontent yaratilmaydi)

insert into public.course_modules (id, org_id, course_id, title, order_index, status) values

($q$ETH1$q$, (select org_id from public.courses where id=$q$ETHICS$q$), $q$ETHICS$q$, $q$Etika va deontologiya asoslari$q$, 1, $q$published$q$),
($q$ETH2$q$, (select org_id from public.courses where id=$q$ETHICS$q$), $q$ETHICS$q$, $q$Bemor huquqlari va xabardor rozilik$q$, 2, $q$published$q$),
($q$ETH3$q$, (select org_id from public.courses where id=$q$ETHICS$q$), $q$ETHICS$q$, $q$Maxfiylik va tibbiy sir$q$, 3, $q$published$q$),
($q$COM1$q$, (select org_id from public.courses where id=$q$COMM$q$), $q$COMM$q$, $q$Salomlashish, tinglash va savol berish$q$, 1, $q$published$q$),
($q$COM2$q$, (select org_id from public.courses where id=$q$COMM$q$), $q$COMM$q$, $q$Konflikt va agressiv bemor$q$, 2, $q$published$q$),
($q$COM3$q$, (select org_id from public.courses where id=$q$COMM$q$), $q$COMM$q$, $q$Qarindoshlar va yomon xabar$q$, 3, $q$published$q$),
($q$SAF1$q$, (select org_id from public.courses where id=$q$SAFETY$q$), $q$SAFETY$q$, $q$Bemorni identifikatsiya qilish va dori xavfsizligi$q$, 1, $q$published$q$),
($q$SAF2$q$, (select org_id from public.courses where id=$q$SAFETY$q$), $q$SAFETY$q$, $q$Yiqilish profilaktikasi va shoshilinch javob$q$, 2, $q$published$q$),
($q$SAF3$q$, (select org_id from public.courses where id=$q$SAFETY$q$), $q$SAFETY$q$, $q$Tibbiy xatolar va incident reporting$q$, 3, $q$published$q$),
($q$IPC1$q$, (select org_id from public.courses where id=$q$IPC$q$), $q$IPC$q$, $q$Qo'l gigiyenasi va PPE$q$, 1, $q$published$q$),
($q$IPC2$q$, (select org_id from public.courses where id=$q$IPC$q$), $q$IPC$q$, $q$Sterilizatsiya, dezinfeksiya, chiqindilar$q$, 2, $q$published$q$),
($q$PH1$q$, (select org_id from public.courses where id=$q$PH$q$), $q$PH$q$, $q$Sog'liqni saqlash tizimi va profilaktika$q$, 1, $q$published$q$),
($q$PH2$q$, (select org_id from public.courses where id=$q$PH$q$), $q$PH$q$, $q$Epidemiologiya va yuqumli kasalliklar$q$, 2, $q$published$q$),
($q$PH3$q$, (select org_id from public.courses where id=$q$PH$q$), $q$PH$q$, $q$Sog'lom turmush tarzi va risk faktorlar$q$, 3, $q$published$q$),
($q$SAL1$q$, (select org_id from public.courses where id=$q$SALES$q$), $q$SALES$q$, $q$Sales Fundamentals: etik sotuv$q$, 1, $q$published$q$),
($q$SAL2$q$, (select org_id from public.courses where id=$q$SALES$q$), $q$SALES$q$, $q$Registratura uchun: telefon va messenjer sotuvi$q$, 2, $q$published$q$),
($q$SAL3$q$, (select org_id from public.courses where id=$q$SALES$q$), $q$SALES$q$, $q$Shifokorlar uchun: davolash rejasini tushuntirish$q$, 3, $q$published$q$),
($q$SAL4$q$, (select org_id from public.courses where id=$q$SALES$q$), $q$SALES$q$, $q$Hamshira va sanitarkalar uchun: service culture$q$, 4, $q$published$q$),
($q$REC1$q$, (select org_id from public.courses where id=$q$RECEPTION_START$q$), $q$RECEPTION_START$q$, $q$Reception etiquette va bemorni ro'yxatga olish$q$, 1, $q$published$q$),
($q$REC2$q$, (select org_id from public.courses where id=$q$RECEPTION_START$q$), $q$RECEPTION_START$q$, $q$Appointment booking, CRM, no-show$q$, 2, $q$published$q$),
($q$REC3$q$, (select org_id from public.courses where id=$q$RECEPTION_START$q$), $q$RECEPTION_START$q$, $q$Medical terminology va shoshilinch holatni tanish$q$, 3, $q$published$q$),
($q$RS1$q$, (select org_id from public.courses where id=$q$RESIDENT_START$q$), $q$RESIDENT_START$q$, $q$Klinik fikrlash va hujjatlashtirish$q$, 1, $q$published$q$),
($q$RS2$q$, (select org_id from public.courses where id=$q$RESIDENT_START$q$), $q$RESIDENT_START$q$, $q$Shoshilinch holatlar: ABCDE$q$, 2, $q$published$q$),
($q$CB1$q$, (select org_id from public.courses where id=$q$CARDIO_BASIC$q$), $q$CARDIO_BASIC$q$, $q$EKG interpretatsiyasi$q$, 1, $q$published$q$),
($q$CB2$q$, (select org_id from public.courses where id=$q$CARDIO_BASIC$q$), $q$CARDIO_BASIC$q$, $q$O'tkir koronar sindrom$q$, 2, $q$published$q$),
($q$CB3$q$, (select org_id from public.courses where id=$q$CARDIO_BASIC$q$), $q$CARDIO_BASIC$q$, $q$Yurak yetishmovchiligi va arterial gipertenziya$q$, 3, $q$published$q$),
($q$DE1$q$, (select org_id from public.courses where id=$q$DOC_EM$q$), $q$DOC_EM$q$, $q$Shoshilinch holatlarni boshqarish$q$, 1, $q$published$q$),
($q$DE2$q$, (select org_id from public.courses where id=$q$DOC_EM$q$), $q$DOC_EM$q$, $q$Laboratoriya va dori tanlash$q$, 2, $q$published$q$),
($q$NC1$q$, (select org_id from public.courses where id=$q$NURSING_CORE$q$), $q$NURSING_CORE$q$, $q$Vital signs va monitoring$q$, 1, $q$published$q$),
($q$NC2$q$, (select org_id from public.courses where id=$q$NURSING_CORE$q$), $q$NURSING_CORE$q$, $q$Dori kiritish, IV terapiya, aseptika$q$, 2, $q$published$q$),
($q$SC1$q$, (select org_id from public.courses where id=$q$SANITARY_CORE$q$), $q$SANITARY_CORE$q$, $q$Tozalash va dezinfeksiya protokollari$q$, 1, $q$published$q$),
($q$SC2$q$, (select org_id from public.courses where id=$q$SANITARY_CORE$q$), $q$SANITARY_CORE$q$, $q$Chiqindilar, PPE va bemor bilan muomala$q$, 2, $q$published$q$),
($q$DA1$q$, (select org_id from public.courses where id=$q$DOCASSIST_CORE$q$), $q$DOCASSIST_CORE$q$, $q$Bemorni tayyorlash va EKG$q$, 1, $q$published$q$),
($q$DA2$q$, (select org_id from public.courses where id=$q$DOCASSIST_CORE$q$), $q$DOCASSIST_CORE$q$, $q$Shifokor workflow va hujjatlar$q$, 2, $q$published$q$)
on conflict (id) do nothing;

insert into public.lessons (org_id, module_id, title, content_type, content, order_index, estimated_minutes, status)
select m.org_id, v.module_id, v.title, v.ct, v.body, v.ord, v.mins, v.st from (values
($q$ETH1$q$, $q$Tibbiy etikaning 4 tamoyili$q$, $q$text$q$, $q$<p>Zamonaviy tibbiy etika 4 asosiy tamoyilga tayanadi (Beauchamp & Childress):</p>
<ul><li><b>Avtonomiya</b> — bemor o'z tanasi va davolanishi haqida qaror qabul qilish huquqiga ega. Shifokor ma'lumot beradi, qaror bemorniki.</li>
<li><b>Beneficence (foyda keltirish)</b> — har bir harakat bemor manfaati uchun.</li>
<li><b>Non-maleficence (zarar yetkazmaslik)</b> — "Primum non nocere": foyda xavfdan yuqori bo'lishi kerak.</li>
<li><b>Adolat</b> — resurslar va yordam teng, kamsitishsiz taqsimlanadi.</li></ul>
<div class="note">Deontologiya — tibbiyot xodimining burch va xulq qoidalari majmui: hamkasblar, bemor va jamiyat oldidagi majburiyatlar.</div>$q$, 1, 8, $q$published$q$),
($q$ETH1$q$, $q$Professional xulq$q$, $q$text$q$, $q$<ul><li>Bemor bilan munosabat — hurmat, xushmuomalalik, shaxsiy chegaralar.</li>
<li>Hamkasbni bemor oldida tanqid qilmaslik; muammolar — rahbariyat orqali.</li>
<li>Sovg'a va manfaatlar to'qnashuvi: qaror bemor manfaatidan kelib chiqib qabul qilinadi, farmatsevtik kompaniya yoki shaxsiy foydadan emas.</li>
<li>Kiyim, gigiyena, nishon (bejik) — bemor ishonchining birinchi omili.</li></ul>$q$, 2, 6, $q$published$q$),
($q$ETH2$q$, $q$Xabardor rozilik (informed consent)$q$, $q$text$q$, $q$<p>Har qanday tekshiruv yoki muolajadan oldin bemorga tushunarli tilda quyidagilar tushuntiriladi:</p>
<ol><li>Tashxis va muolajaning maqsadi</li><li>Kutilayotgan foyda</li><li>Xavf va asoratlar</li><li>Muqobil usullar (shu jumladan davolanmaslik oqibati)</li></ol>
<p>Rozilik <b>ixtiyoriy</b> bo'lishi, bemor <b>muomalaga layoqatli</b> bo'lishi va istalgan vaqtda <b>qaytarib olinishi</b> mumkin. Voyaga yetmaganlar uchun — ota-ona yoki qonuniy vakil.</p>
<div class="note">Shoshilinch holatda, bemor hushsiz va vakil yo'q bo'lsa, hayotni saqlash uchun zarur yordam roziliksiz ko'rsatiladi va hujjatlashtiriladi.</div>$q$, 1, 8, $q$published$q$),
($q$ETH2$q$, $q$Bemor huquqlari$q$, $q$text$q$, $q$<ul><li>Hurmatli munosabat va kamsitilmaslik</li><li>O'z tashxisi haqida to'liq ma'lumot olish</li><li>Shifokorni tanlash, ikkinchi fikr so'rash</li><li>Muolajadan bosh tortish</li><li>Tibbiy sir saqlanishi</li><li>Shikoyat qilish</li></ul>$q$, 2, 5, $q$published$q$),
($q$ETH3$q$, $q$Tibbiy sir$q$, $q$text$q$, $q$<p>Bemorning tashxisi, tekshiruv natijalari, hatto klinikaga murojaat qilgani faktining o'zi ham <b>tibbiy sir</b> hisoblanadi.</p>
<ul><li>Telefonda natijani faqat shaxsini tasdiqlagan bemorning o'ziga yoki u ruxsat bergan shaxsga aytish.</li>
<li>Koridorda, liftda bemor haqida gaplashmaslik.</li>
<li>Kompyuter ekranini qulflash, parolni hech kimga bermaslik.</li>
<li>Bemor rasmini ijtimoiy tarmoqqa uning yozma roziligisiz joylamaslik.</li></ul>
<div class="note">Istisnolar qonun bilan belgilanadi: masalan, tergov organlarining rasmiy so'rovi yoki xavfli yuqumli kasallik haqida xabar berish majburiyati.</div>$q$, 1, 7, $q$published$q$),
($q$COM1$q$, $q$Birinchi 30 soniya$q$, $q$text$q$, $q$<p>Bemor klinika haqidagi taassurotini birinchi 30 soniyada shakllantiradi.</p>
<ol><li>Ko'z bilan aloqa va tabassum</li><li>Salomlashish va o'zini tanishtirish: <i>"Assalomu alaykum, men hamshira Dilnoza bo'laman"</i></li><li>Bemorni ismi bilan murojaat qilish</li><li>"Sizga qanday yordam bera olaman?"</li></ol>$q$, 1, 6, $q$published$q$),
($q$COM1$q$, $q$Faol tinglash va savol turlari$q$, $q$text$q$, $q$<ul><li><b>Ochiq savollar</b> — suhbat boshida: "Nima sizni bezovta qilyapti?"</li>
<li><b>Yopiq savollar</b> — aniqlashtirish uchun: "Og'riq kechasi kuchayadimi?"</li>
<li><b>Summarizatsiya</b> — "Demak, 3 kundan beri bosh og'rig'i va ko'ngil aynishi bor, to'g'rimi?"</li>
<li>Bemorni gapining o'rtasida bo'lmaslik — tadqiqotlarga ko'ra shifokorlar bemorni o'rtacha 11–20 soniyada to'xtatadi.</li></ul>$q$, 2, 8, $q$published$q$),
($q$COM2$q$, $q$Konfliktni boshqarish: LEAP/HEARD$q$, $q$text$q$, $q$<p><b>HEARD</b> modeli:</p>
<ul><li><b>H</b>ear — to'liq eshiting, gapini bo'lmang</li><li><b>E</b>mpathize — "Sizni tushunaman, kutish juda charchatadi"</li><li><b>A</b>pologize — vaziyat uchun uzr</li><li><b>R</b>esolve — aniq yechim taklif qiling</li><li><b>D</b>iagnose — sababini tahlil qilib, takrorlanmasligini ta'minlang</li></ul>
<p>Agressiv bemor bilan: ovozni pasaytirish, xavfsiz masofa, chiqish yo'lini ochiq qoldirish, yolg'iz qolmaslik, kerak bo'lsa xavfsizlik xizmatini chaqirish.</p>$q$, 1, 8, $q$published$q$),
($q$COM3$q$, $q$SPIKES protokoli$q$, $q$text$q$, $q$<p>Yomon xabarni yetkazish uchun <b>SPIKES</b>:</p>
<ol><li><b>S</b>etting — alohida xona, o'tirib, telefonni o'chirib</li><li><b>P</b>erception — bemor nimani biladi?</li><li><b>I</b>nvitation — qancha ma'lumot olishni xohlaydi?</li><li><b>K</b>nowledge — oddiy tilda, "ogohlantiruvchi gap" bilan boshlang</li><li><b>E</b>motions — his-tuyg'uga empatiya bilan javob</li><li><b>S</b>trategy & Summary — keyingi reja</li></ol>$q$, 1, 10, $q$published$q$),
($q$SAF1$q$, $q$Ikki identifikator qoidasi$q$, $q$text$q$, $q$<p>Har qanday muolaja, dori berish, qon olishdan oldin bemor <b>kamida 2 ta identifikator</b> bilan tasdiqlanadi: <b>to'liq ism-familiya + tug'ilgan sana</b> (yoki tibbiy karta raqami).</p>
<p>Palata raqami yoki karavot raqami identifikator <b>emas</b>. Bemordan "Siz Aliyevmisiz?" deb emas, "Ism-familiyangiz va tug'ilgan sanangizni ayting" deb so'raladi.</p>$q$, 1, 6, $q$published$q$),
($q$SAF1$q$, $q$Dori xavfsizligi: '5 to'g'ri'$q$, $q$text$q$, $q$<ol><li>To'g'ri bemor</li><li>To'g'ri dori</li><li>To'g'ri doza</li><li>To'g'ri yo'l (per os, v/i, m/i…)</li><li>To'g'ri vaqt</li></ol>
<p>Qo'shimcha: to'g'ri hujjatlashtirish va allergiyani tekshirish. <b>High-alert</b> dorilar (insulin, geparin, kaliy xlorid konsentrati, opioidlar) ikki xodim tomonidan mustaqil tekshiriladi.</p>$q$, 2, 8, $q$published$q$),
($q$SAF2$q$, $q$Yiqilish xavfi$q$, $q$text$q$, $q$<p>Xavf omillari: 65+ yosh, sedativ dorilar, gipotenziya, oldingi yiqilish, kognitiv buzilish. Choralar: karavot past holatda, tormoz qulflangan, chaqiruv tugmasi qo'l yetadigan joyda, sirpanmaydigan poyabzal, tunda yorug'lik, xavf belgisi (bilaguzuk).</p>$q$, 1, 6, $q$published$q$),
($q$SAF2$q$, $q$Shoshilinch holat: 'Code Blue'$q$, $q$text$q$, $q$<p>Bemor javob bermasa: xavfsizlikni ta'minlang → javobni tekshiring → <b>yordam chaqiring (Code Blue) va defibrillyator keltiring</b> → nafas va pulsni ≤10 soniyada tekshiring → yo'q bo'lsa darhol CPR 30:2.</p>$q$, 2, 6, $q$published$q$),
($q$SAF3$q$, $q$Xatolar madaniyati$q$, $q$text$q$, $q$<p>Xatolarning aksariyati tizim nuqsonidan kelib chiqadi (Swiss cheese modeli). <b>Just culture</b> — xato haqida xabar bergan xodim jazolanmaydi; maqsad — tizimni tuzatish.</p>
<p>Incident report: nima, qachon, qayerda, oqibati, ko'rilgan chora. <b>Near miss</b> (bemorga yetib bormagan xato) ham albatta yoziladi.</p>$q$, 1, 7, $q$published$q$),
($q$IPC1$q$, $q$WHO: qo'l gigiyenasining 5 lahzasi$q$, $q$text$q$, $q$<ol><li>Bemorga tegishdan <b>oldin</b></li><li>Aseptik muolajadan <b>oldin</b></li><li>Biologik suyuqlik bilan kontaktdan <b>keyin</b></li><li>Bemorga tegishdan <b>keyin</b></li><li>Bemor atrofidagi buyumlarga tegishdan <b>keyin</b></li></ol>
<p>Spirtli antiseptik: 20–30 soniya. Sovun va suv: 40–60 soniya — qo'l ko'rinarli ifloslanganda va <i>C. difficile</i> holatlarida majburiy.</p>$q$, 1, 7, $q$published$q$),
($q$IPC1$q$, $q$PPE kiyish va yechish tartibi$q$, $q$text$q$, $q$<p><b>Kiyish:</b> xalat → niqob/respirator → ko'zoynak/shit → qo'lqop.</p>
<p><b>Yechish:</b> qo'lqop → ko'zoynak/shit → xalat → niqob → <b>qo'l gigiyenasi</b>. Eng ifloslangan qism birinchi yechiladi.</p>$q$, 2, 7, $q$published$q$),
($q$IPC2$q$, $q$Spaulding tasnifi$q$, $q$text$q$, $q$<ul><li><b>Kritik</b> (steril to'qimaga kiradi: jarrohlik asboblari) → sterilizatsiya</li><li><b>Yarim kritik</b> (shilliq qavat: endoskop) → yuqori darajali dezinfeksiya</li><li><b>Nokritik</b> (butun teri: tonometr manjeti) → past darajali dezinfeksiya</li></ul>$q$, 1, 7, $q$published$q$),
($q$IPC2$q$, $q$Tibbiy chiqindilar va igna jarohati$q$, $q$text$q$, $q$<p>Chiqindilar sinflarga ajratiladi; o'tkir buyumlar (igna, skalpel) faqat <b>teshilmaydigan konteynerga</b>, 3/4 qismi to'lganda yopiladi. Ignaga qalpoqcha <b>qayta kiyg'izilmaydi</b>.</p>
<p><b>Needle-stick bo'lsa:</b> jarohatni oqar suv va sovun bilan yuving (siqmang, ishqalamang) → darhol mas'ulga xabar → bemor va xodim qon tahlili (HIV, HBV, HCV) → zarur bo'lsa post-ekspozitsion profilaktika (HIV PEP imkon qadar 2 soat ichida, 72 soatdan kechiktirmay).</p>$q$, 2, 8, $q$published$q$),
($q$PH1$q$, $q$Profilaktika darajalari$q$, $q$text$q$, $q$<ul><li><b>Birlamchi</b> — kasallik paydo bo'lishining oldini olish (emlash, sog'lom ovqatlanish, chekishni tashlash)</li><li><b>Ikkilamchi</b> — erta aniqlash (skrining: mammografiya, AQB o'lchash, glyukoza)</li><li><b>Uchlamchi</b> — asoratlarni kamaytirish, reabilitatsiya</li></ul>$q$, 1, 7, $q$published$q$),
($q$PH1$q$, $q$Skrining tamoyillari$q$, $q$text$q$, $q$<p>Yaxshi skrining: kasallik keng tarqalgan va jiddiy, erta bosqichda davolash samarali, test sezgir, arzon va xavfsiz. <b>Sezuvchanlik</b> — kasallarni to'g'ri aniqlash ulushi; <b>spetsifiklik</b> — sog'lomlarni to'g'ri aniqlash ulushi.</p>$q$, 2, 6, $q$published$q$),
($q$PH2$q$, $q$Epidemiologiya asoslari$q$, $q$text$q$, $q$<ul><li><b>Insidens</b> — ma'lum davrdagi <i>yangi</i> holatlar soni</li><li><b>Prevalens</b> — ma'lum vaqtdagi <i>barcha</i> mavjud holatlar</li><li><b>Epidemik zanjir:</b> manba → yuqish yo'li → moyil organizm. Zanjirning istalgan bo'g'inini uzish tarqalishni to'xtatadi.</li><li><b>Kollektiv immunitet</b> — aholining yetarli qismi emlanganda emlanmaganlar ham himoyalanadi.</li></ul>$q$, 1, 8, $q$published$q$),
($q$PH2$q$, $q$Emlash$q$, $q$text$q$, $q$<p>Emlash — eng samarali birlamchi profilaktika. Milliy emlash kalendariga rioya qilish, sovuq zanjir (+2…+8 °C) saqlash, emlashdan keyingi kuzatuv (30 daqiqa) va nojo'ya reaksiyalarni qayd etish.</p>$q$, 2, 6, $q$published$q$),
($q$PH3$q$, $q$Yuqumli bo'lmagan kasalliklar risk faktorlari$q$, $q$text$q$, $q$<p>Asosiy o'zgartirsa bo'ladigan omillar: chekish, nosog'lom ovqatlanish (ortiqcha tuz, shakar), jismoniy faolsizlik, spirtli ichimliklar, arterial gipertenziya, semizlik, dislipidemiya, giperglikemiya.</p>
<p>WHO tavsiyasi: kattalar haftasiga kamida 150 daqiqa o'rtacha jismoniy faollik; tuz iste'moli kuniga 5 g dan kam.</p>$q$, 1, 7, $q$published$q$),
($q$SAL1$q$, $q$Medical service sales nima?$q$, $q$text$q$, $q$<p>Tibbiyotda "sotuv" — bemorga <b>unga haqiqatan kerak bo'lgan</b> xizmatni tushuntirish va uni klinikaga to'g'ri yo'naltirish. Asosiy qoida: <b>tavsiya faqat tibbiy ko'rsatma asosida</b>.</p>
<ol><li>Ehtiyojni aniqlash (savollar orqali)</li><li>Xizmatni tushuntirish: nima, nima uchun, qancha turadi, qancha vaqt</li><li>E'tirozga javob</li><li>Keyingi qadamni belgilash (appointment)</li><li>Follow-up</li></ol>
<p>KPI: consultation conversion, appointment conversion, no-show rate, patient retention, referral (tavsiya bo'yicha kelganlar).</p>$q$, 1, 8, $q$published$q$),
($q$SAL1$q$, $q$Cross-selling va etika$q$, $q$text$q$, $q$<p>Cross-selling — bemorga tibbiy ko'rsatmaga mos qo'shimcha xizmat taklif qilish (masalan, gipertenziyali bemorga EKG va lipid profili). Ko'rsatmasiz tekshiruv buyurish — etikaga zid va bemor ishonchini yo'qotadi.</p>$q$, 2, 5, $q$published$q$),
($q$SAL2$q$, $q$Telefon skripti$q$, $q$text$q$, $q$<ol><li><b>Salom:</b> "Assalomu alaykum, Impuls klinikasi, ismim Sevara, qanday yordam bera olaman?" (3 gudokgacha javob)</li><li><b>Ehtiyoj:</b> "Sizni nima bezovta qilyapti? Qachondan beri?"</li><li><b>Yo'naltirish:</b> mos mutaxassis va uning tajribasini qisqa aytish</li><li><b>Taklif:</b> "Ertaga 10:00 yoki 15:30 — qaysi biri qulay?" (ikki variantli tanlov)</li><li><b>Tasdiqlash:</b> ism, telefon, vaqt, manzil, nima olib kelish kerak</li><li><b>Eslatma:</b> qabuldan bir kun oldin SMS/Telegram — no-show profilaktikasi</li></ol>$q$, 1, 10, $q$published$q$),
($q$SAL2$q$, $q$'Qimmat ekan' degan bemor$q$, $q$text$q$, $q$<p>Narxni himoya qilmang — <b>qiymatni</b> tushuntiring: "Tushunaman. Bu narxga shifokor ko'rigi, EKG va natijani tushuntirish kiradi. Shifokorimiz 15 yillik tajribaga ega." Narx so'ragan bemorga avval 1–2 aniqlovchi savol bering — bu suhbatni davom ettiradi.</p>
<p>WhatsApp/Telegram'da: 5 daqiqa ichida javob, shablonlar, ovozli xabar o'rniga aniq matn, oxirida aniq taklif.</p>$q$, 2, 6, $q$published$q$),
($q$SAL3$q$, $q$Treatment adherence va ethical recommendation$q$, $q$text$q$, $q$<ul><li>Tashxis va rejani oddiy tilda, 3 asosiy fikrda tushuntiring.</li><li><b>Teach-back:</b> "Uyda qanday qabul qilishingizni menga aytib bering-chi?"</li><li>Tekshiruv nima uchun kerakligini va natija qanday qaror qabul qilishga ta'sir qilishini ayting.</li><li>Nazorat qabuli sanasini <b>shu yerning o'zida</b> belgilang — bemorni yo'qotmaslikning eng samarali usuli.</li><li>Moliyaviy imkoniyatni hisobga olib, ustuvor tekshiruvlarni ajrating.</li></ul>$q$, 1, 9, $q$published$q$),
($q$SAL4$q$, $q$Xizmat madaniyati$q$, $q$text$q$, $q$<ul><li>Bemorni kutib olish: salom, ism bilan murojaat, yo'l ko'rsatish (qo'l bilan emas — kuzatib borish).</li><li>Tozalik — klinika sifatining bemor ko'radigan birinchi belgisi.</li><li>Bemor savoliga "bilmayman" emas — "aniqlab beraman" deb javob berish.</li><li>Qo'shimcha xizmat haqida savol bo'lsa — shifokorga yo'naltirish, o'zi tashxis yoki tavsiya bermaslik.</li></ul>$q$, 1, 7, $q$published$q$),
($q$REC1$q$, $q$Registratura standarti$q$, $q$text$q$, $q$<ul><li>Bemor kelganda 10 soniya ichida e'tibor (band bo'lsangiz ham ko'z bilan aloqa va "bir daqiqa").</li><li>Ro'yxatga olish: F.I.Sh., tug'ilgan sana, telefon, pasport/ID ma'lumotlari, murojaat sababi, qanday bilib kelgani (marketing manbai).</li><li>Ma'lumotlarni CRM/MIS'ga to'liq va xatosiz kiritish.</li></ul>$q$, 1, 7, $q$published$q$),
($q$REC2$q$, $q$Yozuv va CRM$q$, $q$text$q$, $q$<p>Har bir murojaat CRM'da: manba, sabab, natija (yozildi / o'ylab ko'radi / rad etdi). "O'ylab ko'raman" degan bemorga 24 soat ichida follow-up. No-show darajasi maqsadi: &lt;10%.</p>$q$, 1, 7, $q$published$q$),
($q$REC3$q$, $q$Qizil bayroqlar$q$, $q$text$q$, $q$<p>Registrator tashxis qo'ymaydi, lekin quyidagi shikoyatlarda bemorni <b>navbatsiz, darhol shifokorga</b> yo'naltiradi yoki 103 ni chaqiradi:</p>
<ul><li>Ko'krak qafasidagi kuchli og'riq, nafas qisishi</li><li>Yuz qiyshayishi, qo'l-oyoqda to'satdan kuchsizlik, nutq buzilishi (insult belgilari)</li><li>Hushini yo'qotish, tutqanoq</li><li>Kuchli qon ketishi</li><li>Homilador ayolda qon ketishi yoki kuchli og'riq</li><li>Bolada yuqori isitma bilan letargiya, toshma</li></ul>$q$, 1, 8, $q$published$q$),
($q$RS1$q$, $q$Klinik fikrlash$q$, $q$text$q$, $q$<p>Shikoyat → anamnez → ko'rik → <b>differensial diagnoz</b> (eng xavflisi va eng ehtimolligi) → maqsadli tekshiruv → ishchi tashxis → reja → qayta baholash.</p><p>SOAP yozuvi: Subjective, Objective, Assessment, Plan.</p>$q$, 1, 8, $q$published$q$),
($q$RS2$q$, $q$ABCDE yondashuvi$q$, $q$text$q$, $q$<p>Og'ir bemor: <b>A</b>irway → <b>B</b>reathing → <b>C</b>irculation → <b>D</b>isability → <b>E</b>xposure. Har bir bosqichda topilgan muammo darhol hal qilinadi, keyin keyingisiga o'tiladi. Qayta baholash — doimiy.</p><p>Sepsis: qSOFA (NOS ≥22, sistolik AQB ≤100, ong o'zgarishi). Gumon bo'lsa 1 soat ichida qon ekmasi, laktat, keng spektrli antibiotik, kristalloid.</p>$q$, 1, 10, $q$published$q$),
($q$CB1$q$, $q$EKG ni tizimli o'qish$q$, $q$clinical_case$q$, $q$<ol><li>Ritm va ChSS</li><li>Elektr o'qi</li><li>P to'lqin, PR (0.12–0.20 s)</li><li>QRS kengligi (&lt;0.12 s)</li><li>ST segment va T to'lqin</li><li>QTc (erkak &lt;450 ms, ayol &lt;460 ms)</li></ol>
<p><b>STEMI mezoni:</b> ≥2 qo'shni tarmoqda ST elevatsiyasi (V2–V3 da erkak ≥40 yosh ≥2 mm, &lt;40 yosh ≥2.5 mm, ayol ≥1.5 mm; boshqa tarmoqlarda ≥1 mm).</p>$q$, 1, 12, $q$published$q$),
($q$CB2$q$, $q$STEMI taktikasi (ESC 2023)$q$, $q$text$q$, $q$<ul><li>Maqsad: birinchi tibbiy kontaktdan reperfuziyagacha — <b>birlamchi PCI ≤120 daqiqa</b>; imkoni bo'lmasa fibrinoliz 10 daqiqa ichida.</li><li>Aspirin yuklama doza, P2Y12 ingibitori, antikoagulyant (geparin).</li><li><b>Kardiogen shok</b>da — shoshilinch PCI, fibrinoliz ikkinchi o'rinda.</li><li>Gipotenziyada nitratlar <b>qarshi ko'rsatma</b>; o'ng qorincha infarktida ham.</li></ul>$q$, 1, 12, $q$published$q$),
($q$CB3$q$, $q$HFrEF farmakoterapiyasi$q$, $q$text$q$, $q$<p>Kamaygan otish fraksiyali YuYe (EF ≤40%) uchun "4 ustun": <b>ARNI/IAPF, beta-bloker, MRA, SGLT2 ingibitori</b>. Diuretiklar — dimlanish belgilarida simptomatik.</p><p>Arterial gipertenziya: maqsadli AQB ko'pchilik bemorlarda &lt;130/80 (toqat qilsa); boshlang'ich terapiya ko'pincha ikki dorili kombinatsiya.</p>$q$, 1, 10, $q$published$q$),
($q$DE1$q$, $q$Anafilaksiya$q$, $q$text$q$, $q$<p>Birinchi navbatdagi dori — <b>adrenalin 0.5 mg (0.5 ml 1:1000) m/i</b>, son old-lateral yuzasiga; samara bo'lmasa 5 daqiqadan keyin takror. Bemorni yotqizish, oyoqlarni ko'tarish, kislorod, v/i suyuqlik. Antigistamin va steroidlar — ikkinchi qator.</p>$q$, 1, 8, $q$published$q$),
($q$DE1$q$, $q$Gipoglikemiya$q$, $q$text$q$, $q$<p>Glyukoza &lt;3.9 mmol/l. Hushida — 15–20 g tez so'riladigan uglevod; hushsiz — 40% glyukoza v/i yoki glyukagon 1 mg m/i. 15 daqiqadan keyin qayta o'lchash.</p>$q$, 2, 5, $q$published$q$),
($q$DE2$q$, $q$Laboratoriya natijalari$q$, $q$text$q$, $q$<p>Giperkaliemiya (K⁺ &gt;6.0 yoki EKG o'zgarishlari bilan): avval <b>kalsiy glyukonat v/i</b> (miokardni himoya), keyin insulin+glyukoza, salbutamol; kaliyni chiqarish choralari.</p><p>Antikoagulyatsiya: varfarin — INR nazorati (odatda 2–3); DOAC — buyrak funksiyasiga qarab doza.</p>$q$, 1, 8, $q$published$q$),
($q$NC1$q$, $q$Hayotiy ko'rsatkichlar normasi (kattalar)$q$, $q$text$q$, $q$<table class="tbl"><tr><th>Ko'rsatkich</th><th>Norma</th></tr><tr><td>AQB</td><td>&lt;120/80 optimal; ≥140/90 — gipertenziya</td></tr><tr><td>Puls</td><td>60–100 /daq</td></tr><tr><td>Nafas soni</td><td>12–20 /daq</td></tr><tr><td>Harorat</td><td>36.1–37.2 °C</td></tr><tr><td>SpO₂</td><td>≥95% (KOAK bemorlarida maqsad 88–92%)</td></tr></table>
<p>AQB o'lchash: bemor 5 daqiqa tinch o'tiradi, manjet yurak sathida, to'g'ri o'lchamdagi manjet; birinchi tashrifda ikkala qo'lda.</p>$q$, 1, 8, $q$published$q$),
($q$NC2$q$, $q$IV kateter va flebitni oldini olish$q$, $q$text$q$, $q$<ul><li>Aseptika: qo'l gigiyenasi, teri antisepsiyasi (masalan, 2% xlorgeksidin + spirt), qurishini kutish.</li><li>Kateterni har smenada baholash (VIP shkalasi); flebit belgilarida olib tashlash.</li><li>Kateter qo'yilgan sana va vaqt yoziladi.</li></ul>$q$, 1, 9, $q$published$q$),
($q$NC2$q$, $q$Yara parvarishi va siydik kateteri$q$, $q$text$q$, $q$<p>Yara bog'lashda aseptik "no-touch" texnika. Siydik kateteri — faqat ko'rsatma bo'lsa va imkon qadar tez olib tashlanadi (CAUTI profilaktikasi); siydik qopi qovuq sathidan pastda.</p>$q$, 2, 6, $q$published$q$),
($q$SC1$q$, $q$Tozalash qoidasi: 'tozadan iflosga, yuqoridan pastga'$q$, $q$text$q$, $q$<div class="visual"><div>⬆️ Yuqoridan</div><div>➡️</div><div>⬇️ Pastga</div></div><div class="visual"><div>✨ Toza zona</div><div>➡️</div><div>🦠 Iflos zona</div></div>
<ul><li>Har bir zona uchun alohida rangli latta va chelak.</li><li>Dezinfektant eritmasi yo'riqnomadagi konsentratsiya va <b>ekspozitsiya vaqti</b> bo'yicha.</li><li>Qon to'kilganda: qo'lqop → absorbent bilan yopish → dezinfektant → yig'ishtirish → qayta dezinfeksiya.</li></ul>$q$, 1, 6, $q$published$q$),
($q$SC2$q$, $q$Chiqindi ranglari$q$, $q$text$q$, $q$<div class="visual"><div>⬜/⚫ Maishiy (A)</div><div>🟨 Xavfli tibbiy (B)</div><div>🟥 O'ta xavfli (V)</div><div>📦 O'tkir buyumlar konteyneri</div></div><p>Igna va shishalarni qo'l bilan yig'mang. Qop 3/4 to'lganda bog'lanadi. Bemor palatasida — taqillatib kirish, salom, o'zini tanishtirish, bemor sirini saqlash.</p>$q$, 1, 6, $q$published$q$),
($q$DA1$q$, $q$12 tarmoqli EKG elektrodlari$q$, $q$text$q$, $q$<ul><li>V1 — IV qovurg'alararo, to'sh o'ng chetida</li><li>V2 — IV qovurg'alararo, to'sh chap chetida</li><li>V3 — V2 va V4 o'rtasida</li><li>V4 — V qovurg'alararo, o'rta o'mrov chizig'ida</li><li>V5 — oldingi qo'ltiq chizig'i, V4 sathida</li><li>V6 — o'rta qo'ltiq chizig'i, V4 sathida</li></ul><p>Qo'l-oyoq elektrodlari: qizil — o'ng qo'l, sariq — chap qo'l, yashil — chap oyoq, qora — o'ng oyoq.</p>$q$, 1, 8, $q$published$q$),
($q$DA2$q$, $q$Qabul oqimi$q$, $q$text$q$, $q$<p>Bemorni chaqirish → identifikatsiya → vital signs → shikoyatni qisqa yozish → shifokorga topshirish → ko'rikdan keyin tavsiyalarni tushuntirish, tahlil va nazorat qabuliga yozish.</p>$q$, 1, 6, $q$published$q$)
) v(module_id, title, ct, body, ord, mins, st) join public.course_modules m on m.id = v.module_id
where not exists (select 1 from public.lessons l where l.module_id = v.module_id and l.order_index = v.ord);

insert into public.learning_paths (org_id, code, title, status) select o.id, v.code, v.title, $q$published$q$ from public.organizations o cross join (values
($q$RES_START$q$, $q$Resident Starter Program$q$),
($q$RES_DEV$q$, $q$Residency Development Program$q$),
($q$JR_DOC$q$, $q$Junior Doctor Program$q$),
($q$DOC_PRO$q$, $q$Doctor Professional Development$q$),
($q$NURSE$q$, $q$Nursing Academy$q$),
($q$SANITARY$q$, $q$Healthcare Assistant / Sanitary Staff Academy$q$),
($q$DOC_ASSIST$q$, $q$Doctor Assistant Academy$q$),
($q$RECEPTION$q$, $q$Reception & Registration Academy$q$),
($q$ADMIN$q$, $q$Hospital Administration Academy$q$)
) v(code, title) where o.id = $q$00000000-0000-0000-0000-000000000001$q$ on conflict (org_id, code) do nothing;

insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required)
select p.org_id, p.id, v.course_id, v.ord, v.req from (values
($q$RES_START$q$, $q$ETHICS$q$, 1, true),
($q$RES_START$q$, $q$COMM$q$, 2, true),
($q$RES_START$q$, $q$SAFETY$q$, 3, true),
($q$RES_START$q$, $q$IPC$q$, 4, true),
($q$RES_START$q$, $q$PH$q$, 5, true),
($q$RES_START$q$, $q$SALES$q$, 6, true),
($q$RES_START$q$, $q$RESIDENT_START$q$, 7, true),
($q$RES_DEV$q$, $q$ETHICS$q$, 1, true),
($q$RES_DEV$q$, $q$COMM$q$, 2, true),
($q$RES_DEV$q$, $q$SAFETY$q$, 3, true),
($q$RES_DEV$q$, $q$IPC$q$, 4, true),
($q$RES_DEV$q$, $q$PH$q$, 5, true),
($q$RES_DEV$q$, $q$SALES$q$, 6, true),
($q$RES_DEV$q$, $q$RESIDENT_START$q$, 7, true),
($q$JR_DOC$q$, $q$ETHICS$q$, 1, true),
($q$JR_DOC$q$, $q$COMM$q$, 2, true),
($q$JR_DOC$q$, $q$SAFETY$q$, 3, true),
($q$JR_DOC$q$, $q$IPC$q$, 4, true),
($q$JR_DOC$q$, $q$PH$q$, 5, true),
($q$JR_DOC$q$, $q$SALES$q$, 6, true),
($q$JR_DOC$q$, $q$RESIDENT_START$q$, 7, true),
($q$JR_DOC$q$, $q$DOC_EM$q$, 8, true),
($q$DOC_PRO$q$, $q$ETHICS$q$, 1, true),
($q$DOC_PRO$q$, $q$COMM$q$, 2, true),
($q$DOC_PRO$q$, $q$SAFETY$q$, 3, true),
($q$DOC_PRO$q$, $q$IPC$q$, 4, true),
($q$DOC_PRO$q$, $q$PH$q$, 5, true),
($q$DOC_PRO$q$, $q$SALES$q$, 6, true),
($q$DOC_PRO$q$, $q$DOC_EM$q$, 7, true),
($q$NURSE$q$, $q$ETHICS$q$, 1, true),
($q$NURSE$q$, $q$COMM$q$, 2, true),
($q$NURSE$q$, $q$SAFETY$q$, 3, true),
($q$NURSE$q$, $q$IPC$q$, 4, true),
($q$NURSE$q$, $q$PH$q$, 5, true),
($q$NURSE$q$, $q$SALES$q$, 6, true),
($q$NURSE$q$, $q$NURSING_CORE$q$, 7, true),
($q$SANITARY$q$, $q$ETHICS$q$, 1, true),
($q$SANITARY$q$, $q$COMM$q$, 2, true),
($q$SANITARY$q$, $q$SAFETY$q$, 3, true),
($q$SANITARY$q$, $q$IPC$q$, 4, true),
($q$SANITARY$q$, $q$PH$q$, 5, true),
($q$SANITARY$q$, $q$SALES$q$, 6, true),
($q$SANITARY$q$, $q$SANITARY_CORE$q$, 7, true),
($q$DOC_ASSIST$q$, $q$ETHICS$q$, 1, true),
($q$DOC_ASSIST$q$, $q$COMM$q$, 2, true),
($q$DOC_ASSIST$q$, $q$SAFETY$q$, 3, true),
($q$DOC_ASSIST$q$, $q$IPC$q$, 4, true),
($q$DOC_ASSIST$q$, $q$PH$q$, 5, true),
($q$DOC_ASSIST$q$, $q$SALES$q$, 6, true),
($q$DOC_ASSIST$q$, $q$DOCASSIST_CORE$q$, 7, true),
($q$RECEPTION$q$, $q$ETHICS$q$, 1, true),
($q$RECEPTION$q$, $q$COMM$q$, 2, true),
($q$RECEPTION$q$, $q$SAFETY$q$, 3, true),
($q$RECEPTION$q$, $q$IPC$q$, 4, true),
($q$RECEPTION$q$, $q$PH$q$, 5, true),
($q$RECEPTION$q$, $q$SALES$q$, 6, true),
($q$RECEPTION$q$, $q$RECEPTION_START$q$, 7, true),
($q$ADMIN$q$, $q$ETHICS$q$, 1, true),
($q$ADMIN$q$, $q$COMM$q$, 2, true),
($q$ADMIN$q$, $q$SAFETY$q$, 3, true),
($q$ADMIN$q$, $q$IPC$q$, 4, true),
($q$ADMIN$q$, $q$PH$q$, 5, true),
($q$ADMIN$q$, $q$SALES$q$, 6, true)
) v(path_code, course_id, ord, req) join public.learning_paths p on p.code = v.path_code and p.org_id = $q$00000000-0000-0000-0000-000000000001$q$
join public.courses c on c.id = v.course_id on conflict (path_id, course_id) do nothing;
