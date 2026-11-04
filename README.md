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
