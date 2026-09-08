# Porți care nu pot fi demonstrate integral pe `windows-latest` fără ecran

Workflow-ul validează automat codul și produsul instalat. Următoarele aspecte
rămân în afara dovezii unui runner GitHub fără sesiune desktop interactivă:

| Poartă | Motiv | Ce dovedește workflow-ul în loc |
|---|---|---|
| Dublu clic fizic | Runnerul nu are utilizator care operează mouse-ul | Invocă exact `00_INSTALEAZA_SI_PORNESTE_EMP_UTILITY.bat` prin `cmd.exe` și verifică exit code-ul și rapoartele |
| Aspectul vizual al ferestrei/browserului | Nu există captură de ecran desktop interactivă garantată | Verifică HTTP 200, HTML-ul servit, identitatea, versiunea și antetele anti-cache |
| Click real pe scurtătura Desktop/Start | Shell-ul Explorer nu este o sesiune desktop interactivă stabilă | Validatorul deschide fișierele `.lnk`, verifică ținta/argumentele și pornește aceleași scurtături programatic |
| Windows 11 AMD64 client exact | Eticheta `windows-latest` este o imagine Windows Server x64 aleasă de GitHub, nu Windows 11 Desktop | Raportul păstrează caption-ul OS real, arhitectura și run ID-ul; nu îl redenumește Windows 11 |
| Absența fizică a Pythonului global | Imaginile GitHub găzduite includ unelte de dezvoltare | În timpul produsului, `PATH` exclude uneltele globale, `-I` este obligatoriu, iar calea/modulele trebuie să provină din runtime-ul privat |
| Restart complet al sistemului de operare | VM-ul găzduit nu poate reporni și continua același job cu starea garantată | Testează oprirea/repornirea procesului, persistența datelor, repararea și reinstalarea în același job |
| Randare umană a tuturor documentelor | Testul automat nu poate aprecia subiectiv toate paginile | Deschide structural DOCX/XLSX/PDF, controlează semantic F1–F5 și verifică pagini/text/legături |
| Compatibilitate cu antivirus, imprimantă sau scanner real | Aceste periferice și politici locale nu există pe runner | Testează fișiere sintetice, OCR Tesseract privat și I/O pe discul Windows al runnerului |
| Date reale ale beneficiarului | Datele clientului sunt excluse intenționat din CI | Rulează numai proiectele sintetice JT, MT și MT+JT incluse în sursă |

Aceste limite nu sunt convertite în PASS. Workflow-ul poate emite doar
`BUILD WINDOWS VALIDAT PE DATE SINTETICE` după trecerea tuturor porților pe
care runnerul le poate executa.
