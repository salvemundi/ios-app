# Meldingen: status en acceptatiepilot

Het profiel maakt onderscheid tussen toestemming op de iPhone en registratie van het toestel bij de backend. Toestemming alleen betekent niet dat er al pushberichten worden bezorgd. Mislukte Apple-registratie en mislukte backendkoppeling zijn zichtbaar. De app probeert de koppeling opnieuw bij verversen. Voorkeuren zijn pas wijzigbaar nadat de server ze heeft geladen; tijdens opslaan zijn de schakelaars tijdelijk geblokkeerd.

De bestaande acceptatiewerker ondersteunt aanmeldingen, betalingen, activiteitswijzigingen en herinneringen voor gewone activiteiten. De eerste synchronisatie zet een uitgangspunt en verstuurt geen historische meldingen. De werker gebruikt een verplichte lijst van toegestane testleden; productie wordt niet geactiveerd.

## Nog nodig voor een echte bezorgtest

1. Bevestig op de server welke database acceptatie gebruikt voordat de handmatige notificatiemigratie wordt toegepast. Gedeelde infrastructuur bewijst geen gescheiden databases.
2. Controleer of de migratie al is uitgevoerd en de aparte acceptatiewerker draait. Deze controle is nog niet op de server uitgevoerd.
3. Configureer de Apple APNs-sleutel uitsluitend op de server, met team-ID, key-ID en topic `nl.salvemundi.ios`. In de GitHub-omgeving Acceptance zijn geen APNs-geheimnamen aangetroffen; de aparte serverinstellingen zijn hiermee niet gecontroleerd.
4. Kies expliciet de testleden, schakel meldingen op hun iPhones in en bevestig de toestelregistratie. De status ‘gekoppeld’ in de app bevestigt de API-aanvraag, niet de werking van de werker of daadwerkelijke bezorging.
5. Voer daarna een gecontroleerde pilot uit met een testaanmelding en testwijziging. Voor TestFlight is de afzonderlijke acceptance-optie voor productie-APNs nodig; de API blijft acceptatie.

De serverinstructies staan in de website-repo onder `docs/mobile-notifications-acceptance.md`. Deze verbetering heeft geen databasewijzigingen uitgevoerd en geen echte pushberichten verstuurd.
