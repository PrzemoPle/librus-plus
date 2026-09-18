# Roadmapa Dzienniczka

Uzgodniony backlog usprawnień. Robimy od góry; punkt skreślamy, gdy trafi do TestFlight.

Punkty 1–4 są w TestFlight od buildu 1.1.0 (1005), punkt 5 od 1.2.0 (1007), 15.09.2026.

## Kolejność

1. ~~**Data i pozycja świeżej wiadomości**~~ — zrobione 15.09.2026, błąd. Parser brał datę z piątej komórki wiersza; wiersz nowej wiadomości ma dodatkową komórkę, więc data nie parsowała się i wiadomość spadała na dół. Parser szuka teraz komórki z datą, przyjmuje też `15.09.2026 07:45`, a wiadomość bez daty ląduje na górze. W Diagnostyce jest przycisk „Kopiuj surowy HTML skrzynki” na wypadek kolejnego układu.
2. ~~**Jasny / ciemny / systemowy**~~ — zrobione 15.09.2026; przełącznik w Ustawieniach, `preferredColorScheme` na korzeniu aplikacji, wybór w `AppStorage`. Mała zmiana.
3. ~~**Kolory przedmiotów**~~ — zrobione 15.09.2026; opcjonalne: domyślnie nic się nie zmienia, kolor ma tylko przedmiot, któremu użytkownik go nadał. Ekran w Ustawieniach z listą przedmiotów (z planu i ocen) i paletą kilkunastu kolorów. Kolor widoczny w planie (pasek przy lekcji), na pulpicie i w ocenach. Zapis lokalny, wspólny dla obojga dzieci po nazwie przedmiotu. Średnia zmiana.
4. ~~**Własny układ zakładek**~~ — zrobione 15.09.2026; Ustawienia → Wygląd → Zakładki: wybór trzech ekranów między Pulpitem a Więcej (np. Terminarz zamiast Frekwencji); reszta zostaje w „Więcej”. Zapis lokalny, per telefon. Średnia zmiana. Przeciąganie ikon palcem jak na ekranie głównym iOS nie jest dostępne dla pasków zakładek na iPhonie, stąd lista wyboru.
5. ~~**Widżety**~~ — w TestFlight 15.09.2026 (1.2.0). Kod: cel `MojLibrusWidget` w `project.yml` (bundle id `pl.plewinscy.dzienniczek.widget`, grupa `group.pl.plewinscy.dzienniczek`), widżet planu (mały, średni, duży) z imieniem wybranego dziecka w nagłówku, workflow podpisuje dwa cele dwoma profilami, skrypt rejestruje App ID widżetu i włącza App Groups. Grupa App Group założona i przypisana ręcznie w portalu (API tego nie umie); profile odnowione skryptem z `--no-pause`. Wybór dziecka per widżet (konfiguracja w edycji widżetu) — później, na razie widżet pokazuje dziecko wybrane w aplikacji.
6. **Otwarte testy** — publiczny link TestFlight dla innych rodziców z klasy. Wymaga Beta App Review pierwszego buildu (zwykle 1–2 dni) i uzupełnienia opisu testów. Ryzyko: Apple może dopytać o nieoficjalnego klienta Librusa i użycie nazwy „Librus” w opisie. To proces w App Store Connect, nie kod; robimy na końcu, gdy reszta będzie stabilna.

## Runda 2 — spostrzeżenia z 18.09.2026

7. **Data na Pulpicie** — w prawym górnym rogu, obok przełącznika dziecka: „piątek, 18 wrz”. Odświeża się sama o północy.
8. **Karta „Plan na dziś” jest przyciskiem** — przenosi do zakładki Plan na bieżący tydzień (w weekend na następny). Gdy Plan nie jest w pasku zakładek, otwiera się jako ekran z Pulpitu.
9. **Karta „Najbliższy wpis w terminarzu” jest przyciskiem** — przenosi do Terminarza, przewija do tego wpisu i podświetla go na dwie sekundy.
10. **Przesuwanie między dziećmi** — poziome przesunięcie po treści ekranu pokazuje następne lub poprzednie dziecko, z przesunięciem ekranu w stronę gestu. Działa na Pulpicie, w Planie (na liście lekcji; nagłówek tygodnia nadal przewija tygodnie), Ocenach, Frekwencji, Terminarzu i Uwagach. Wiadomości i Ogłoszenia są wyłączone, bo ich wiersze mają własny gest przesunięcia. Oglądany tydzień planu zostaje ten sam po zmianie dziecka.

## Ustalenia

- Kontakt w Ustawieniach i adres do opinii z TestFlight: przemyslaw@plewinski.pl.
- Jeśli Beta App Review odrzuci otwarte testy, plan B: rodzice jako testerzy wewnętrzni (użytkownicy App Store Connect z rolą Customer Support ograniczoną do tej aplikacji, do 100 osób, bez przeglądu Apple).

## Poza listą, do rozważenia

- Własna ikona aplikacji zamiast „L++” z oryginału.
- Powiadomienia push zamiast odświeżania w tle (wymaga serwera, więc raczej nie).
