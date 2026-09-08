# Ce testează workflow-ul Windows

| Etapă | Control automat |
|---|---|
| Identitate runner | URL rulare, run ID, commit, imagine OS și arhitectură |
| Rehidratare sursă | Ordinea părților și SHA-256 al arhivei sursă |
| Parser | Toate fișierele PS1 prin parserul Windows PowerShell; orice eroare oprește jobul |
| Build | Sintaxă Python, runtime PE AMD64, 16 wheel-uri, ordine dependențe, politică offline, arbore curat |
| Reproductibilitate | Două ZIP-uri construite succesiv trebuie să fie byte-identice |
| Integritate | SHA-256 ZIP și verificare independentă 223/223 a manifestului din arhivă |
| Instalare | Exact punctul `00_INSTALEAZA_SI_PORNESTE_EMP_UTILITY.bat`, de la zero |
| Python privat | `python.exe -I`, `import site`, `typing_extensions`, `docx`, toate modulele și DLL-urile native |
| Tesseract privat | Executabil privat, DLL-uri, modelele `ron`, `eng`, `osd` |
| Offline | Reguli firewall pentru procesele produsului, proxy blocat și `sitecustomize` care refuză conexiunile externe |
| OCR | PDF scanat sintetic creat pe Windows și citit efectiv cu Tesseract privat |
| Server | Pornire, răspuns HTTP 200 pentru API și pagină, identitate `EMP UTILITY`, versiunea 1.3 |
| Cache/identitate | `Cache-Control: no-store`, fără marcă publică veche sau versiuni 1.1/1.2/4.x în pagina servită |
| GIS | Tabel, numerotare, denumiri, E(Y)/N(X), coordonate lipsă, persistență și două proiecte izolate |
| F1–F5 | Fiecare formular separat și semantic, materiale existente, UM, cantități, trasabilitate și regenerare |
| Exporturi | DOCX, XLSX și PDF deschise structural; perechi complete |
| Temporare | Zero `.partial`, `.tmp` și `_in_lucru` |
| Persistență | Oprire și repornire proces cu recitirea proiectului |
| Backup/restaurare | Corupere sintetică a bazei și restaurare automată din backup |
| Reparare | Acțiunea `repara` păstrează santinela din date |
| Reinstalare | Reinstalare nesupravegheată, date păstrate și import gate repetat |
| Rollback | Eșec controlat după runtime, componente parțiale șterse, date păstrate |
| Publicare | Rapoarte și loguri întotdeauna; ZIP validat numai după succes integral |
