# Activiteitenbeheer en aanmeldingenwidget

Het activiteitenbeheer is onderdeel van de native iPhone-app. De app gebruikt de bestaande acceptance-backend, accounts, commissies en activiteiten. Productie blijft een afzonderlijke releasebeslissing.

## Rechten

De server haalt bij elke beheer- en widgetaanvraag de huidige commissielidmaatschappen op. Het activiteitenrecht geeft commissieleden toegang tot de activiteiten van hun eigen commissies. ICT, bestuur en kandidaten met de bestaande brede beheerrechten krijgen het bijbehorende ruimere overzicht. Alleen de bestaande bewerkrollen krijgen de functies voor aanmaken, aanpassen, verwijderen, handmatige aanmeldingen en deelnemersberichten.

De app gebruikt de door de server geretourneerde mogelijkheden voor de knoppen; verborgen knoppen zijn geen beveiliging. De server controleert activiteit, doelcommissie en deelnemer opnieuw. Een deelnemer-ID van een andere activiteit geeft geen toegang. Een ingetrokken sessie of verloren rechten worden bij de volgende aanvraag geweigerd.

Deelnemerslijsten blijven in het geheugen van de app. Er is geen offline deelnemersarchief. Exporteren is een bewuste gebruikersactie; CSV/PDF-uitvoer kan persoonsgegevens bevatten en wordt alleen via de normale deelinterface aangeboden. Een nieuwe autorisatiecontrole gaat aan de export vooraf.

## Beheerfuncties

- Activiteiten bekijken, aanmaken, aanpassen, plannen/publiceren en verwijderen.
- Beschrijving, datum/tijd, tarieven, capaciteit, commissie, contact, ledenbeperking en afbeelding/video beheren.
- Aanmeldingen doorzoeken en filteren, handmatig toevoegen of verwijderen, aanwezigheidsstatus wijzigen en QR-codes scannen.
- Deelnemers exporteren en via een bevestigde actie een bericht sturen.

Handmatig toevoegen volgt de website: een betaalde/bevestigde aanmelding zonder automatische betaling. Verwijderen voert geen automatische terugbetaling uit. De app vraagt bevestiging bij deze acties. Een bericht gaat naar de door de server geselecteerde deelnemers van de betreffende activiteit, niet naar willekeurige aangeleverde adressen.

## Widget

De widget toont aantallen van meerdere toegestane activiteiten, met bevestigde/open aanmeldingen en aanwezigheid waar ruimte is. Deelnemersnamen, e-mailadressen, telefoonnummers en QR-codes gaan niet naar de widget.

De widget gebruikt een apart counts-only toegangsbewijs in de gedeelde Keychain. Het volledige app-inlogbewijs blijft in de private Keychain-groep. Het widgetbewijs verloopt uiterlijk na zeven dagen of bij het verlopen van de bovenliggende app-sessie. Elke aanvraag controleert de bovenliggende sessie en actuele commissierechten; het bewijs werkt niet voor deelnemerslijsten of beheerwijzigingen.

Samenvattingen verlopen na maximaal vijftien minuten. Bij afmelden of geweigerde toegang worden het gedeelde bewijs en de samenvatting gewist. iOS bepaalt de daadwerkelijke verversingsmomenten; de widget is geen realtime teller. Open de app om direct opnieuw te controleren en een verlopen widgetverbinding te vernieuwen.

## Apple-configuratie

Beide targets gebruiken App Group `group.nl.salvemundi.ios`. Voor Keychain Sharing staat de eigen private groep als eerste en `$(AppIdentifierPrefix)nl.salvemundi.ios.shared` als tweede. Dit houdt bestaande app-inloggegevens privé en maakt uitsluitend het beperkte widgetbewijs deelbaar.

Gebruik hetzelfde Apple-team voor app en widget. Laat Xcode de provisioningprofielen na de capabilitywijziging vernieuwen. Voeg de widget op een fysieke iPhone toe en test commissie-, leider- en brede beheerrollen, verlies van rechten, afmelden en verlopen sessies.

## Doorlopend tickets scannen

Open op Home Tickets scannen en kies de activiteit. Bevoegde leden hebben ook een eigen Beheer-tab met een scanknop bovenaan; vanuit een activiteit is Tickets scannen rechtstreeks bereikbaar. De camera blijft open; een korte popup meldt Ingecheckt, Al ingecheckt, Geen geldig ticket of Nog niet betaald. Na de popup wordt automatisch verder gescand. Een code die in beeld blijft wordt onderdrukt; een andere code die tijdens de popup verschijnt wordt niet vergeten. De server bepaalt of iemand aanwezig wordt gezet. Bij een verbindingsfout wordt geen lokale aanwezigheid bevestigd. De bestaande scanfunctie onder Aanmeldingen en aanwezigheid gebruikt dezelfde scanner.
