# Roadmapa Dzienniczka

Uzgodniony backlog usprawnień. Robimy od góry; punkt skreślamy, gdy trafi do TestFlight.

## Kolejność

1. ~~**Data i pozycja świeżej wiadomości**~~ — zrobione 15.09.2026, błąd. Parser brał datę z piątej komórki wiersza; wiersz nowej wiadomości ma dodatkową komórkę, więc data nie parsowała się i wiadomość spadała na dół. Parser szuka teraz komórki z datą, przyjmuje też `15.09.2026 07:45`, a wiadomość bez daty ląduje na górze. W Diagnostyce jest przycisk „Kopiuj surowy HTML skrzynki” na wypadek kolejnego układu.
2. **Jasny / ciemny / systemowy** — przełącznik w Ustawieniach, `preferredColorScheme` na korzeniu aplikacji, wybór w `AppStorage`. Mała zmiana.
3. **Kolory przedmiotów** — opcjonalne: domyślnie nic się nie zmienia, kolor ma tylko przedmiot, któremu użytkownik go nadał. Ekran w Ustawieniach z listą przedmiotów (z planu i ocen) i paletą kilkunastu kolorów. Kolor widoczny w planie (pasek przy lekcji), na pulpicie i w ocenach. Zapis lokalny, wspólny dla obojga dzieci po nazwie przedmiotu. Średnia zmiana.
4. **Własny układ zakładek** — w Ustawieniach wybór, które cztery ekrany są w pasku obok Pulpitu (np. Terminarz zamiast Frekwencji); reszta zostaje w „Więcej”. Zapis lokalny, per telefon. Średnia zmiana. Przeciąganie ikon palcem jak na ekranie głównym iOS nie jest dostępne dla pasków zakładek na iPhonie, stąd lista wyboru.
5. **Widżety** — kod widżetu planu lekcji jest w repo (`Sources/Widget`), ale wymaga App Group i drugiego profilu provisioning dla rozszerzenia. Do zrobienia: rejestracja bundle id rozszerzenia i App Group przez skrypt podpisywania, drugi profil, podpis dwóch celów w workflow, włączenie celu w `project.yml`, widżet z wyborem dziecka. Największa zmiana, głównie po stronie podpisywania.
6. **Otwarte testy** — publiczny link TestFlight dla innych rodziców z klasy. Wymaga Beta App Review pierwszego buildu (zwykle 1–2 dni) i uzupełnienia opisu testów. Ryzyko: Apple może dopytać o nieoficjalnego klienta Librusa i użycie nazwy „Librus” w opisie. To proces w App Store Connect, nie kod; robimy na końcu, gdy reszta będzie stabilna.

## Ustalenia

- Kontakt w Ustawieniach i adres do opinii z TestFlight: przemyslaw@plewinski.pl.
- Jeśli Beta App Review odrzuci otwarte testy, plan B: rodzice jako testerzy wewnętrzni (użytkownicy App Store Connect z rolą Customer Support ograniczoną do tej aplikacji, do 100 osób, bez przeglądu Apple).

## Poza listą, do rozważenia

- Własna ikona aplikacji zamiast „L++” z oryginału.
- Powiadomienia push zamiast odświeżania w tle (wymaga serwera, więc raczej nie).
