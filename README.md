# Weasy Voice – FlutterFlow integráció, Android próba

Magyar beszédfelismerés a helyi Whisper base-q5_1 modellel. Nem használ külső API-t vagy Android rendszerfelismerőt. A csomag a FlutterFlow-ban lévő felülethez készült; nem külön alkalmazás.

## Állapot és követelmények

- Android 13+ (API 33), ARM64. iOS nincs megvalósítva.
- A beépített modell 59,7 MB; első indításkor ellenőrzötten átmásolódik az alkalmazás privát tárhelyére. A fordításban és a telepített alkalmazásban is számolni kell ezzel a mérettel.
- Ez integrációs próba, még nem telefonon tesztelt FlutterFlow-build. A korábbi külön Android-próbában a magyar felismerés, szürkülés és görgetés működött; a mostani gyorsítást telefonon még nem mértük.
- A natív C++ könyvtár és a Java plugin lefordult. A Java szókövetési, hangpuffer- és görgetési próbák sikeresek. Teljes Flutter/Dart- és Gradle-ellenőrzés itt nem futott; a Dart-próbák forrása a tests könyvtárban van.

## Bekötés a meglévő FlutterFlow-projektbe

1. A ZIP tartalmát, közvetlenül a pubspec.yaml-t tartalmazó könyvtárat tedd Git-repozitóriumba. A modell és az android/src/main/jniLibs/arm64-v8a/libweasy_whisper.so is szükséges; ne használj Git LFS mutatófájlt a valódi fájl helyett.
2. FlutterFlow-ban add hozzá a weasy_voice csomagot Git-függőségként, a tényleges repozitórium URL-jével és rögzített commitjával. Android minimum SDK: 33. A meglévő kameraengedély maradjon; a plugin deklarálja a mikrofonengedélyt. Teljes natív APK-build kell, a webes előnézet nem teszteli ezt a motort.
3. A flutterflow/weasy_video_capture.integration.dart a megkapott Weasy-exporthoz elkészített integrációs változat. Előbb hasonlítsd össze a FlutterFlow aktuális WeasyVideoCapture kódjával; csak a kamera/hang/súgó részek változzanak. Az újabb szkriptkezelést, editor színeket, navigációt és 150 px paddingot ne írd felül régi exportból. A paraméterek neve és típusa nem változik.
4. A kamera létrehozása: WeasyCaptureController.create(description). A camera csak képet rögzít (enableAudio:false). A plugin egyetlen mikrofonból írja a PCM hangot és adja ugyanazokat a mintákat a felismerőnek. A szokásos enableAudio:true kamerához NE indítsd hozzá külön ezt a mikrofont.
5. A meglévő gombok a session.start/pause/resume/finish metódusait hívják. A finish visszatérési értéke már hangos MP4: ezt kell átadni a meglévő review/galériamentésnek. A kamera saját ideiglenes fájlja néma.
6. A session maradjon a meglévő store-ban szünet alatti editor-navigációnál. Back aktív felvételnél előbb await session.pause(), és csak siker után navigáljon. Visszatéréskor ne indítson automatikusan felvételt. A controller kezeli a háttérbe kerülés miatti szüneteltetést is; a telefonos kamera-életciklust ellenőrizni kell.
7. A kamera fölötti szöveg: WeasyPrompter(controller:session,text:promptText,fontFamily:promptFont,fontSize:promptSize). Fehér olvasatlan, #91918B olvasott, #041622 háttér 31%-on. A felismert szavak változtatják az olvasási pontot; az animáció kizárólag ezt a pontot követi. Kézi visszagörgetés felfüggeszti a felismerést, majd új horgonyról indítja, a hátralévő szöveg ismét fehér.
8. A player bezárása után, kizárólag sikeres galériamentés vagy megerősített elvetés esetén cleanupAfterDecision(). Hibás mentésnél ne töröld az ideiglenes fájlokat. A megőrzött munkamenet nem áll helyre alkalmazásfolyamat-leállítás után.

## Gyorsítás

A 0.1.4-es változat a sorfelúszás ritmusát módosítja: fix 180 ms helyett a sor szóhosszához és a közelmúltban megfigyelt átlagos olvasási tempóhoz igazodó, 450–950 ms közötti, lágy szinuszos animációt használ. Több már felismert sor felzárkóztatásakor soronként legfeljebb 650 ms a mozgás. A hosszú felismerési szünetek, a nagy ugrások és a kézi visszagörgetés nem kalibrálják félre a tanult tempót. A ritmusbecslés nem indít önálló görgetést és nem szürkít szavakat: a célpontokat továbbra is csak a szöveghez illesztett felismerés módosítja. Külön kalibrációs képernyő és a tempó tartós mentése nincs ebben a változatban; az adott súgó-widget az olvasás közben alkalmazkodik.

A 0.1.3-as változat a szóegyeztetést módosítja. Hosszabb szavaknál kevés betűnyi eltérést, szétírt/egybeírt felismerést és horgonyok között egy betoldott vagy kihagyott szót kezel. Bizonytalan egyezéshez több szavas környezet kell; távolabbi újraszinkronizálást nem indít két rövid gyakori szóra. A kézi visszagörgetés továbbra is új, olvasatlan horgonyt hoz létre. A natív modell, a mikrofonfolyam, a rögzítés és a soranimáció ebben a változatban változatlan. Ez a felismerési hibák okozta megtorpanásokat célozza; a modell telefonos feldolgozási késését nem szünteti meg.

A 0.1.2-es változat soronként léptet: a szürkülés szavanként frissül, de a sor olvasása közben a függőleges helyzet rögzített. Amikor az olvasási pont a következő tördelt sorba ér, egy 180 ms-os animáció egy teljes sorral lép feljebb. Több sor felismerése esetén is külön sorlépések történnek. A kézi visszagörgetés törli a korábbi léptetési célokat. Ehhez a változathoz a kamera- és hangrögzítés, valamint a natív felismerő nem változott.

A 0.1.1-es változatban a hangablak 4 helyett 3 másodperc, a felismerési lépés 250 ms új hang után indítható. Az encoder kontextusa a hanghosszhoz igazodva 1,92–3,2 másodperc, a korábbi fix 5,12 másodperc helyett. Egyszerre egy felismerés fut; a tényleges frissítési idő továbbra is függ a telefon feldolgozási idejétől. A rövidebb kontextus pontosságát telefonon ismét ellenőrizni kell. A görgetési célpont a soron belüli szópozícióhoz igazodik, egy olvasható sornyi helyet hagyva felül. Gyorsabban reagáló, túllövés nélküli mozgás és a betűmérethez igazodó sebességkorlát váltja a korábbi, lassan lecsengő animációt. A felismerés késését ez önmagában nem szünteti meg.

## Egyetlen következő telefonos próba

Olvass 20–30 másodperc magyar szöveget, közben tarts csendet és görgess vissza egy mondatot. Ellenőrizd: késés, valós szürkülés, csendben nincs új előrelépés, kézi újraolvasás után fehér szöveg, videó hangja és szinkronja, Szünet/Folytatás, Back–editor–Start, véglegesítés és galériamentés. Az automatikus felismertetés befejezéséhez kötött gördülés kis utólagos mozgása a már felismert célpontig még lehetséges.

A videóhang most mono 16 kHz PCM-ből kódolódik AAC-ba; ennek minősége eltérhet a korábbi camera csomag hangjától. Hosszú felvételnél, több pause/resume ciklusnál, háttérbe kerülésnél és hívásmegszakításnál külön ellenőrizni kell a hangot és a szinkront.

## Eredet

whisper.cpp commit: d1be6fde11ac6e0407606b4e42fe72d34add8037 (v1.9.5 tag).
Modell: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin
SHA1: a3733eda680ef76256db5fc5dd9de8629e62c5e7.
Licencek: assets/LICENSE-* és NOTICE-android-runtime.txt.
A natív JNI forrás a native könyvtárban található; újrafordításhoz a fenti pontos whisper.cpp forrás, Android NDK r28c, CMake és ARM64 Android33 cél kell. A CMake WHISPER_SOURCE változója adja meg a whisper.cpp helyét. A ZIP nem tartalmaz fejlesztői eszközöket vagy aláírókulcsot.

FlutterFlow hivatalos leírás: https://docs.flutterflow.io/concepts/advanced/method-channels/

## 0.1.5 – folyamatos súgómozgás

A súgó a vizuális soron belüli szópozíciót folyamatos célponttá alakítja. Egyetlen, gyorsulás- és sebességkorlátos követő mozgatja a szöveget; új felismerési eredménykor nem indul újra soronkénti animáció. A meglévő magyar szóegyeztetés és szürkülés továbbra is csak felismert szavakon alapul.

A két eredmény közötti megjelenítési becslés legfeljebb 650 ms-ig és 0,4 sormagasságig tart. Ezután a mozgás a korlátozott célpontra fékez. Ez nem külön beszéd/csend-detektor: rövid kifutás lehetséges, és hosszabb felismerési késést nem tud teljesen elfedni. Kézi görgetés és szünet törli a mozgás becslését. A natív mikrofon- és videóút változatlan.

Az automatikus próbák ellenőrzik a folytonosságot fél másodpercenként érkező eredmények mellett, a nagy felismerési ugrások sebesség- és gyorsuláskorlátját, az eredmények elmaradásakor történő megállást, a kézi visszaállítást, a dokumentum végét és a 30/60 Hz egyezését. A telefonos olvashatóság új APK-val ellenőrizendő.
## 0.1.6 – 1,4 másodperces indulás és felső olvasási sáv

A mozgás első biztos szóegyezéstől számított 1,4 másodperc után indul. Ez nem az első hang fizikai időpontja: a felismerés saját késése hozzáadódik. Új egyezés nem indítja újra az időzítést; kézi visszagörgetés és folytatás nem kap új késleltetést. Új felvétel vagy lecserélt szöveg újraindítja az indulási várakozást.

Az olvasási célpont 0,6 sorral feljebb kerül. A mozgásbecslés két egyezés között legfeljebb 1,4 másodpercig és 0,85 sormagasságig tart; a szürkülés továbbra is kizárólag szóegyezést követ. Csendfelismerés nincs hozzáadva, rövid kifutás ezért lehetséges. A 0.1.5 visszaállási pontja: a7a02e207f76aca63016a63c0a0b45b07fbd1d84.

## 0.1.8 – 10% erősítés a felismerő bemenetén

A 0.1.10-es verzió az eredeti amplitúdó 1,40-szeresét használja (+40%), további 15 százalékpontos emeléssel. Csak a felismerő bemenete változik, a tartománykorlátozás megmarad. A +25%-os visszaállási pont: 8891c0467255b9d45c1b9a7996e0806ff4175090 (0.1.9).

A 0.1.9-es verzió ezt további 15 százalékponttal, az eredeti amplitúdó 1,25-szörösére emeli (+25%). A tartománykorlátozás megmarad; a videó hangja és a görgetés beállításai változatlanok.

A beszédfelismerő mintái 1,10-szeres amplitúdót kapnak, a megengedett tartományra korlátozva. A felismerő saját hangaktivitás-vizsgálata is ezeket a mintákat használja. Az eredeti PCM, a mentett videó hangja, az indulási hangérzékelő és a görgetési beállítások változatlanok. Ez fix, mérsékelt erősítés, nem automatikus hangerőszabályozás vagy zajszűrés. Telefonon kell ellenőrizni, segít-e a halk felolvasásnál.

## 0.1.7 – indulás a hang kezdetétől, elakadás utáni visszatalálás

Az indulási 1,4 másodpercet a meglévő PCM-folyamon érzékelt, legalább 120 ms-os hangaktivitás kezdetétől számoljuk. Nem nyílik második mikrofon. Az energiaérzékelés becslés: erős háttérzaj is kiválthatja, halk beszédet később észlelhet. Már az első szófelismerés előtt elkezdődhet a finom mozgás, de ez önmagában legfeljebb 0,85 sort mozdít és egyetlen szót sem szürkít ki. Újabb hangaktivitás-jelzés nem indítja újra a mozgásbecslést; a további haladáshoz szóegyezés szükséges.

Elakadt, korábban már követett szövegnél két pontos, legalább ötbetűs, a dokumentumban egyedileg előforduló egymás utáni szó is visszaállíthatja a követést a közelben. Tartós elakadáskor a keresési tartomány 20-ról 40 szóra bővül, a távolabbi találat továbbra is legalább három egyező szót kíván. Kézi újrapozicionálás törli az elakadás előzményeit. A videó kódolása, mentése és a meglévő sebesség-/gyorsuláskorlát változatlan. A telefonos javulás mértéke új APK-val ellenőrizendő.
