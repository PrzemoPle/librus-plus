# Librus Plus

> **Fork rodzinny (PrzemoPle).** Ta gałąź różni się od oryginału
> [WebMasterPL/librus-PP](https://github.com/WebMasterPL/librus-PP) jedną rzeczą:
> obsługuje **kilkoro dzieci na jednym Koncie LIBRUS**. Po zalogowaniu aplikacja
> pobiera wszystkie konta Synergia połączone z kontem rodzica, a dziecko przełącza
> się menu w lewym górnym rogu każdego ekranu (albo w Ustawieniach → Dzieci).
> Każde dziecko ma osobną pamięć podręczną, osobne plakietki „nowe”, osobne
> powiadomienia (z imieniem w podtytule) i osobne wpisy w Kalendarzu.
> Reszta — logowanie i ekrany — jak w oryginale poniżej. **Dystrybucja jest inna:
> TestFlight zamiast SideStore** (patrz niżej); sekcja „Jak zainstalować” z oryginału
> tu nie obowiązuje.

## TestFlight — jak to uruchomić (fork)

Nazwa wyświetlana: **Dzienniczek**, bundle id `pl.plewinscy.dzienniczek`, Team
`94MSU24AZ7`. Build robi GitHub Actions (`.github/workflows/testflight.yml`) na
każdy tag `v*` i wysyła go do App Store Connect. Konfiguracja podpisywania jest
jednorazowa i robisz ją sam na Macu — klucz API i certyfikat nie przechodzą przez
nikogo poza Tobą i GitHubem.

1. **Klucz API.** [App Store Connect](https://appstoreconnect.apple.com) → *Użytkownicy
   i dostęp* → *Integracje* → *Klucze zespołu* → „+”. Nazwa `GitHub CI`, rola
   **Admin** (albo *App Manager* z zaznaczonym dostępem do certyfikatów). Pobierz
   plik `AuthKey_XXXXXXXXXX.p8` (Apple daje go tylko raz) i zapisz *Key ID* oraz
   *Issuer ID* z tej samej strony.
2. **Skrypt.** W Terminalu, w katalogu repo:
   ```bash
   python3 scripts/setup_signing.py --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer-id <Issuer ID>
   ```
   Zakłada certyfikat *Apple Distribution*, App ID, profil App Store i wgrywa sześć
   sekretów do repo (`gh secret set`). Klucz i `.p12` zostają w
   `~/Library/Application Support/dzienniczek-signing/`.
3. **Rekord aplikacji** (raz, ręcznie — API tego nie umie): App Store Connect →
   *Moje aplikacje* → „+” → *Nowa aplikacja*: iOS, nazwa unikalna w App Store
   (np. „Dzienniczek Plewińskich”), język polski, Bundle ID `pl.plewinscy.dzienniczek`,
   SKU `dzienniczek`. Nic więcej nie wypełniaj.
4. **Build.** `git tag v1.0.0 && git push origin v1.0.0`. Po 10–15 min build jest
   w App Store Connect → *TestFlight*; przetwarzanie trwa kolejne kilka minut.
5. **Testerzy.** *TestFlight* → *Testy wewnętrzne* → „+” → grupa „Rodzina” → dodaj
   siebie. Żonę najpierw zaproś w *Użytkownicy i dostęp* → „+” (jej Apple ID, rola
   *Developer* wystarczy), a gdy przyjmie zaproszenie — dodaj do grupy. Na
   telefonach: aplikacja **TestFlight** z App Store → zaproszenie z maila →
   *Zainstaluj*. Testy wewnętrzne nie przechodzą przez Beta App Review.
6. **Odświeżanie.** Build TestFlight wygasa po 90 dniach — wystarczy nowy tag
   (`v1.0.1`), TestFlight sam pokaże aktualizację.

Workflow `build.yml` to tylko kontrola kompilacji i testów na każdy push (bez podpisu).

Nieoficjalny klient iOS (SwiftUI) dla dziennika **Librus Synergia**. Funkcjonalnie
wzorowany na [szkolny.eu](https://szkolny.eu), ale obsługuje **wyłącznie Librusa**.

**Bez serwera, bez kont w chmurze, bez telemetrii.** Logujesz się swoim **Kontem LIBRUS**,
a dane trafiają wyłącznie do Keychaina Twojego telefonu i łączą się bezpośrednio z
`*.librus.pl`. Aplikacja **nie jest powiązana z firmą Librus**. Kod jest w całości otwarty.

Nie potrzebujesz Maca ani Xcode: aplikację buduje **GitHub Actions**, a instalujesz ją
przez **SideStore / AltStore** darmowym Apple ID.

> **Wymaga Konta LIBRUS.** Aplikacja — dokładnie jak oficjalna apka Librus — loguje się
> **Kontem LIBRUS** (e-mail + hasło z [konto.librus.pl](https://konto.librus.pl), połączone
> z Twoją Synergią). Sam login szkolny (`1234567u`) **nie zadziała** — bezpośredni login
> `api.librus.pl` (`grant_type=password`) Librus wyłączył w 2026. Jeśli nie masz Konta LIBRUS:
> konto.librus.pl → *Załóż Konto LIBRUS* → połącz z kontem Synergia.

## Funkcje

| Ekran | Źródło danych |
|---|---|
| Pulpit — bieżąca/następna lekcja, dzisiejszy plan, ostatnie oceny, liczniki | agregacja |
| Oceny — wg przedmiotów, średnie ważone, filtr semestru, **kalkulator „co jeśli / ile potrzebuję"** | `api.librus.pl/2.0/Grades` |
| Plan lekcji — tydzień, zastępstwa, odwołania, **zmiana sali**, skok do „dziś" | `.../2.0/Timetables` + `Classrooms` |
| Frekwencja — podsumowanie % + wpisy, wg przedmiotów, filtr semestru | `.../2.0/Attendances` |
| Ogłoszenia — szybki odczyt gestem (jak w Mail) | `.../2.0/SchoolNotices` |
| Terminarz (sprawdziany, kartkówki) | `.../2.0/HomeWorks` |
| Uwagi | `.../2.0/Notes` |
| Rozkład dzwonków (godziny lekcji) | `.../2.0/Schools` (`LessonsRange`) |
| Wiadomości — **odbierane i wysłane**, wysyłanie z wyborem odbiorców, status odczytania | scraping `synergia.librus.pl/wiadomosci` |
| Logowanie | `portal.librus.pl` OAuth → `api/v3/SynergiaAccounts` → Bearer per konto |
| Ustawienia → **Diagnostyka połączenia** — test każdego endpointu + kopiuj raport | — |
| Powiadomienia (osobno: oceny / zmiany w planie / wiadomości), *eksperymentalne* | `BGAppRefreshTask` |
| Ustawienia → **Dodawaj wpisy do Kalendarza** — terminarz w systemowym Kalendarzu | `EventKit` |

Nowe oceny są oznaczane plakietką „NOWE" + liczbą na zakładce (lokalne śledzenie, działa
zawsze, niezależnie od powiadomień w tle). Chwilowy błąd jednego endpointu nie czyści
ekranu — zostają dane z cache (tryb offline).

## Jak zainstalować (dla znajomych)

1. Zainstaluj [SideStore](https://sidestore.io) (raz, z pomocą komputera; potem odświeża
   się sam przez Wi‑Fi). Alternatywa: AltStore + AltServer na PC.
2. W SideStore → **Sources** → **+** i wklej adres źródła:
   ```
   https://github.com/WebMasterPL/librus-PP/releases/latest/download/apps.json
   ```
3. Otwórz „Librus Plus" na liście źródła → **Install**. SideStore podpisze apkę Twoim
   darmowym Apple ID.
4. Uruchom, zaloguj się **e‑mailem Konta LIBRUS** (nie loginem `1234567u`).

**Ograniczenia darmowego Apple ID** (nie da się ich obejść — to polityka Apple):
aplikacja wygasa po **7 dniach**, SideStore odświeża ją w tle gdy telefon jest w sieci;
max **3** sideloadowane aplikacje; brak powiadomień push (i tak nieistotne).

Aktualizacje: gdy wyjdzie nowa wersja, SideStore pokaże **Update** przy aplikacji.

## Jak to zbudować samemu

`.xcodeproj` **nie jest** trzymany w repo — generuje go
[XcodeGen](https://github.com/yonaskolb/XcodeGen) z `project.yml` na runnerze `macos-14`.

- **push na `main`** → CI buduje, testuje, wrzuca artefakt `MojLibrus-ipa`
- **tag `v*`** → dodatkowo publikuje **Release** z `MojLibrus.ipa` i aktualizuje `apps.json`
  (wersja, rozmiar, link) — dlatego źródło SideStore działa „samo"

```
git tag v1.2.3 && git push origin v1.2.3
```

CI buduje **niepodpisany** `.ipa` (`CODE_SIGNING_ALLOWED=NO`) — podpis powstaje dopiero
na telefonie w SideStore. Żeby użyć własnego repo: zmień URL-e w `apps.json` na swoje
(albo pozwól CI je nadpisać przy pierwszym tagu — używa `github.repository`).

## Prywatność

- Dane logowania i tokeny: **tylko Keychain urządzenia**. Nigdzie nie są wysyłane poza `*.librus.pl`.
- Kalendarz: synchronizacja jest **domyślnie wyłączona**. Po włączeniu aplikacja tworzy własny
  kalendarz „Librus Plus" i zapisuje wyłącznie w nim — Twoich wydarzeń nie czyta ani nie zmienia.
  Wyłączenie opcji zostawia kalendarz; osobny przycisk kasuje go razem z wpisami.
- Zero analityki, zero zewnętrznych SDK, zero serwera pośredniczącego.
- Wiadomości: aplikacja czyta stronę `synergia.librus.pl/wiadomosci` jako Twoja przeglądarka
  (sesja web Synergii). Nic nie przechodzi przez nikogo trzeciego.
- „Zgłoś problem" w Ustawieniach otwiera GitHub Issues — nic nie jest wysyłane automatycznie.

## Problemy

- **Coś nie działa?** Ustawienia → **Diagnostyka połączenia** → *Uruchom test* → *Kopiuj raport*.
- **Captcha przy logowaniu** — portal rzadko jej wymaga z IP telefonu. Zaloguj się raz przez
  przeglądarkę na `portal.librus.pl`, odczekaj chwilę i spróbuj ponownie w apce.
- **„Portal nie zwrócił żadnego konta Synergia"** — konto musi być połączone na
  `portal.librus.pl` (*Twoje konta*).
- **Wiadomości** — aplikacja czyta stronę `synergia.librus.pl/wiadomosci` (starszy, ale
  wspólny dla wszystkich szkół interfejs). Jeśli Twoja szkoła ma inny układ skrzynki i coś
  nie działa, dołącz do zgłoszenia linię „Wiadomości" z Diagnostyki — dodam obsługę.
- **Pusty plan lekcji** — sprawdź w Librusie, czy plan klasy jest publiczny.

## Widżet planu lekcji

Kod widżetu jest w repo (`Sources/Widget/`, `Sources/Shared/`), ale **wydawany build go
nie zawiera** — darmowe konto Apple ID nie dostaje profilu provisioning dla rozszerzenia
z App Group, przez co sideload padał (`0xe8008015`). Żeby zbudować z widżetem: przywróć
target `MojLibrusWidget` i `CODE_SIGN_ENTITLEMENTS` w `project.yml` i podpisz kontem
z płatnego programu deweloperskiego.

## Uwaga prawna

Nieoficjalny klient. Odtwarza publiczne API aplikacji mobilnej Librus (te same stałe klienta
OAuth, których używają inne projekty open‑source, m.in. szkolny.eu). Wyłącznie do użytku
edukacyjnego / własnego, z własnym kontem, **na własną odpowiedzialność**. Nie jest powiązany
z firmą Librus sp. z o.o. ani przez nią wspierany. „Librus" i „Synergia" to znaki towarowe
ich właścicieli. Autorzy nie ponoszą odpowiedzialności za ewentualne skutki użycia.

## Architektura (skrót)

```
Sources/
  Auth/      Keychain, Credentials, PortalAuth, LibrusSession (actor: token + refresh)
  Api/       Endpoints, APIError, LibrusAPI (1 metoda / endpoint)
  Models/    Raw/ (Codable 1:1 z JSON) + View/ (modele złączone)
  Store/     DataRepository (@Observable, łączenie po Id, cache), GradeMath, Cache
  Messages/  MessagesClient (actor: sesja Synergia → scraping wiadomości)
  Features/  ekrany SwiftUI
  Widget/ + Shared/   rozszerzenie widżetu (nie budowane) + współdzielony store
Tests/       dekodowanie próbek JSON + testy średnich
```

## Licencja

[MIT](LICENSE).
