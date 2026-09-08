# EMP UTILITY 1.3 R4 — încărcare fără linie de comandă

Acest kit este pregătit pentru un depozit GitHub privat, nou și gol. Nu cere
token, parolă, GitHub Desktop, Git LFS, PowerShell sau comenzi locale.

## Încărcare

1. Descarcă arhiva `EMP-UTILITY-v1.3-R4-KIT-GITHUB-R2.zip`.

2. Extrage arhiva într-un folder obișnuit.

3. Deschide folderul extras `DE_PUS_IN_REPOSITORY`.

4. În GitHub, creează un depozit privat nou.

5. La creare, nu bifa README, `.gitignore` sau licență.

6. Intră în pagina depozitului gol.

7. Apasă `uploading an existing file` sau `Add file` → `Upload files`.

8. Trage în zona de încărcare **conținutul** folderului
   `DE_PUS_IN_REPOSITORY`, nu folderul exterior al kitului.

9. Verifică în lista de încărcare că apar directoarele `.github`, `ci` și
   `payload_parts`, plus fișierul `build_v13.py`.

10. În câmpul mesajului scrie `EMP UTILITY 1.3 R4 Windows CI`.

11. Alege `Commit directly to the main branch`.

12. Apasă `Commit changes`.

13. Deschide fila `Actions` a depozitului.

14. Workflow-ul `EMP UTILITY Windows Acceptance` pornește automat după commit.

15. Dacă GitHub afișează pagina de activare a Actions, apasă o singură dată
    butonul de activare. Nu sunt necesare secrete sau tokenuri configurate de
    utilizator.

16. La terminare, deschide rularea și secțiunea `Artifacts`.

17. Artefactul `...WINDOWS-RAPOARTE...` există și la FAIL și conține cauza
    exactă și rapoartele produse până la oprire.

18. Artefactul `...WINDOWS-VALIDAT...` există numai dacă toate porțile
    automate Windows au trecut.

## Ce se încarcă

Kitul folosește mai puțin de 100 de fișiere, iar fiecare fișier este sub
25 MiB. Runtime-ul mare este împărțit în părți numerotate; workflow-ul îl
reasamblează, îi verifică SHA-256 și extrage sursa înainte de build.

Nu se încarcă date reale, parole, tokenuri, chei API sau proiecte ale
beneficiarului. Datele de test sunt exclusiv sintetice.

## Interpretarea rezultatului

- Job verde și artefact `WINDOWS-VALIDAT`: `BUILD WINDOWS VALIDAT PE DATE SINTETICE`.
- Job roșu: produsul nu este acceptat; cauza exactă este în
  `RAPORT_CI_WINDOWS.json` și în logurile publicate automat.
- Rularea nu dovedește experiența vizuală pe Windows 11 Desktop; limitele sunt
  enumerate în `PORTI_FARA_ECRAN.md`.
