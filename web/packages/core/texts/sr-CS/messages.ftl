message-cant-embed =
    Timffle nije mogao da pokrene Fleš ugrađen na ovoj stranici.
    Možete pokušati da otvorite datoteku u posebnoj kartici da biste izbegli ovaj problem.
message-restored-from-bfcache =
    Vaš pregledač je vratio ovaj Fleš sadržaj iz prethodne sesije.
    Molimo vas da ponovo učitate stranicu za novi početak.
panic-title = Nešto je pošlo po zlu :(
more-info = Dodatne informacije
run-anyway = Ipak pokreni
continue = Nastavi
report-bug = Prijavi grešku
update-ruffle = Ažurirajte Timffle
ruffle-demo = Veb demo
ruffle-desktop = Desktop aplikacija
ruffle-wiki = Pogledajte Ruffle Wiki
enable-hardware-acceleration = Izgleda da je hardversko ubrzanje onemogućeno. Iako Timffle možda radi, može biti veoma spor. Možete saznati kako da omogućite hardversko ubrzanje prateći donju vezu:
enable-hardware-acceleration-link = Česta pitanja - Hardversko ubrzanje u Chrome-u
view-error-details = Prikaži detalje greške
open-in-new-tab = Otvori u novoj kartici
click-to-unmute = Kliknite da biste uključili zvuk
clipboard-message-title = Kopiranje i nalepljivanje u Timffle-u
clipboard-message-description =
    { $variant ->
    *[unsupported] Vaš pregledač ne podržava potpun pristup međuspremniku,
    [access-denied] Pristup baferu je zabranjen,
    } ali uvek možete koristiti ove prečice:
clipboard-message-copy = { " " } za kopiju
clipboard-message-cut = { " " } za sečenje
clipboard-message-paste = { " " } za lepljenje
error-canvas-reload = Ne može se ponovo učitati renderer za platno kada je renderer za platno već u upotrebi.
error-file-protocol =
    Izgleda da koristite Timffle na protokolu "file:".
    Ovo ne funkcioniše jer pregledači blokiraju mnoge funkcije iz bezbednosnih razloga.
    Umesto toga, preporučujemo podešavanje lokalnog servera ili korišćenje veb demo verzije ili desktop aplikacije.
error-javascript-config =
    Timffle je naišao na ozbiljan problem zbog pogrešne konfiguracije JavaSkripta.
    Ako ste administrator servera, preporučujemo vam da proverite detalje greške kako biste saznali koji parametar uzrokuje problem. Takođe možete da konsultujete Timffleov viki za pomoć.
error-wasm-not-found =
    Timffle nije uspeo da učita potrebnu komponentu datoteke ".wasm".
    Ako ste administrator servera, proverite da li je datoteka ispravno otpremljena.
    Ako problem i dalje postoji, možda ćete morati da koristite podešavanje "publicPath": pogledajte Timffleovu viki stranicu za pomoć.
error-wasm-mime-type =
    Timffle je naišao na ozbiljan problem prilikom pokušaja inicijalizacije.
    Ovaj veb server ne služi ".wasm" datoteke sa ispravnim MIME tipom.
    Ako ste administrator servera, obratite se Timffleovom vikiju za pomoć.
error-invalid-swf =
    Timffle ne može da analizira traženu datoteku.
    Najverovatniji razlog je taj što tražena datoteka nije važeći SWF.
error-swf-fetch =
    Timffle nije uspeo da učita Fleš SWF datoteku.
    Najverovatniji razlog je taj što datoteka više ne postoji, pa Timffle nema šta da učita.
    Pokušajte da kontaktirate administratora veb stranice za pomoć.
error-swf-cors =
    Timffle nije uspeo da učita Fleš SWF datoteku.
    Pristup preuzimanju je verovatno blokiran CORS politikom.
    Ako ste administrator servera, pogledajte Timffleovu viki stranicu za pomoć.
error-wasm-cors =
    Timffle nije uspeo da učita potrebnu komponentu datoteke ".wasm".
    Pristup preuzimanju je verovatno blokiran CORS politikom.
    Ako ste administrator servera, pogledajte Timffleovu viki stranicu za pomoć.
error-wasm-invalid =
    Timffle je naišao na ozbiljan problem prilikom pokušaja inicijalizacije.
    Izgleda da ovoj stranici nedostaju ili su nevažeće datoteke za pokretanje Timfflea.
    Ako ste administrator servera, pogledajte Timffleov viki za pomoć.
error-wasm-download =
    Timffle je naišao na ozbiljan problem prilikom pokušaja inicijalizacije.
    Ovo se često može rešiti jednostavnim ponovnim učitavanjem stranice.
    U suprotnom, kontaktirajte administratora sajta.
error-wasm-disabled-on-edge =
    Timffle nije uspeo da učita potrebnu komponentnu datoteku ".wasm".
    Da biste rešili ovaj problem, pokušajte da otvorite podešavanja pregledača, kliknete na "Privatnost, pretraga i usluge", pomerite se nadole i isključite "Poboljšaj bezbednost veba".
    Ovo će omogućiti vašem pregledaču da učita potrebne ".wasm" datoteke.
    Ako problem i dalje postoji, možda ćete morati da koristite drugi pregledač.
error-wasm-unsupported-browser =
    Pregledač koji koristite ne podržava WebAssembly ekstenzije potrebne za rad Timffle-a.
    Molimo vas da pređete na podržani pregledač.
    Lista podržanih pregledača može se naći na Viki stranici.
error-javascript-conflict =
    Timffle je naišao na ozbiljan problem prilikom pokušaja inicijalizacije.
    Izgleda da ova stranica koristi JavaSkript kod koji je u sukobu sa Timffleom.
    Ako ste administrator servera, pozivamo vas da pokušate da otpremite datoteku na praznu stranicu.
error-javascript-conflict-outdated = Takođe možete pokušati da otpremite noviju verziju programa Timffle koja bi mogla da reši problem (trenutna verzija je zastarela: { $buildDate }).
error-csp-conflict =
    Timffle je naišao na ozbiljan problem prilikom pokušaja inicijalizacije.
    Politike bezbednosti sadržaja ovog veb servera ne dozvoljavaju pokretanje potrebne komponente ".wasm".
    Ako ste administrator servera, obratite se Timffleovom vikiju za pomoć.
error-unknown =
    Timffle je naišao na ozbiljan problem prilikom pokušaja prikazivanja ovog Fleš sadržaja.
    { $outdated ->
    [true] Ako ste administrator servera, pokušajte da otpremite noviju verziju Timfflea (trenutna verzija je zastarela: { $buildDate }).
    *[false] Ovo ne bi trebalo da se dešava, pa bismo vam bili veoma zahvalni ako biste prijavili grešku!
    }
