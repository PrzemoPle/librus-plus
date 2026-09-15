# Polityka prywatności aplikacji Dzienniczek

Ostatnia aktualizacja: 15 września 2026

Dzienniczek to nieoficjalna, prywatna aplikacja dla rodziców, która pokazuje dane
z dziennika elektronicznego Librus Synergia: plan lekcji, oceny, frekwencję,
ogłoszenia i wiadomości. Aplikacja nie jest powiązana z firmą Librus sp. z o.o.

## Jakie dane przetwarza aplikacja

- **Dane logowania** do Konta LIBRUS (e-mail i hasło) oraz tokeny sesji. Są
  zapisane wyłącznie w Keychainie Twojego telefonu, zaszyfrowane przez iOS, i nie
  są kopiowane do iCloud ani do żadnego serwera autora aplikacji.
- **Dane z dziennika** (plan lekcji, oceny, frekwencja, ogłoszenia, wiadomości,
  imiona i nazwiska nauczycieli, nazwa szkoły). Są pobierane bezpośrednio z
  serwerów `*.librus.pl` i przechowywane w pamięci podręcznej na telefonie, żeby
  aplikacja działała także bez sieci. Wylogowanie usuwa pamięć podręczną.
- **Ustawienia** (motyw, kolory przedmiotów, układ zakładek, powiadomienia).
  Tylko na telefonie.
- **Kalendarz** — wyłącznie jeśli sam włączysz opcję „Dodawaj wpisy do
  Kalendarza”. Aplikacja tworzy wtedy własny kalendarz i zapisuje w nim wpisy z
  terminarza; Twoich pozostałych wydarzeń nie czyta ani nie zmienia.

## Dokąd trafiają dane

Aplikacja łączy się wyłącznie z serwerami Librus (`portal.librus.pl`,
`api.librus.pl`, `synergia.librus.pl`, `wiadomosci.librus.pl`) i tylko po to,
żeby pobrać Twoje dane lub wysłać napisaną przez Ciebie wiadomość. Nie ma
serwera pośredniczącego, analityki, reklam ani zewnętrznych bibliotek
śledzących. Autor aplikacji nie ma dostępu do Twoich danych.

## Powiadomienia

Powiadomienia o nowych ocenach, zmianach w planie i wiadomościach są lokalne,
generowane na telefonie po odświeżeniu danych. Nie ma powiadomień push z
zewnętrznego serwera.

## TestFlight

Podczas testów przez TestFlight Apple może zbierać dane o awariach i
statystyki użycia zgodnie z własną polityką prywatności TestFlight. Aplikacja
sama nie wysyła takich danych.

## Usunięcie danych

Wyloguj się w Ustawieniach aplikacji (usuwa dane logowania i pamięć
podręczną) albo odinstaluj aplikację. Kalendarz „Dzienniczek” usuwasz
osobnym przyciskiem w Ustawieniach lub w aplikacji Kalendarz.

## Kontakt

Przemysław Plewiński, przemyslaw@plewinski.pl

Kod źródłowy aplikacji jest publiczny: https://github.com/PrzemoPle/librus-plus
