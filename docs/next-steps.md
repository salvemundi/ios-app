# Volgende stappen richting TestFlight en App Store

## 1. Acceptatie op echte iPhones afronden

Test aanmelden, bestaande tickets, betaald/gratis inschrijven en terugkeer uit Mollie. Controleer het nieuwe activiteitenbeheer met een gewoon lid, een commissielid, een commissieleider en een brede beheerder. Test ook het verliezen van rechten, een QR-code van een andere activiteit, annuleren en afmelden.

Gebruik testactiviteiten en testdeelnemers. Bevestig expliciet voordat een deelnemersbericht wordt verzonden. De automatische tests gebruiken geen echte accounts, betalingen of e-mails.

## 2. Widgets en meldingen inrichten

Controleer hetzelfde Apple-team, de App Group en Keychain Sharing voor beide targets. Bouw opnieuw, voeg de aanmeldingenwidget toe en controleer dat alleen toegestane activiteiten verschijnen. Test ook zonder netwerk, na afmelden en na rechtenwijzigingen. Widgetupdates worden door iOS gepland en zijn niet realtime.

Configureer daarna APNs en de bestaande acceptance-notificatiewerker voor uitsluitend goedgekeurde testleden. Controleer eerst de werkelijke databasebestemming en de handmatige notificatiemigratie. De beheer- en widgetuitbreiding zelf vereist geen nieuwe database-tabellen. TestFlight gebruikt productie-APNs; de acceptance-server blijft daarbij acceptance.

## 3. Interne TestFlight-pilot

Maak of controleer de App Store Connect-app onder de organisatie, selecteer het team en archiveer een ondertekende Release-build. Upload de build en begin met een kleine interne testgroep. Verzamel problemen rond login, inschrijvingen, privacy, toegankelijkheid en widgets voordat de groep wordt uitgebreid.

Apple: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/

## 4. Externe ledentest en winkelgegevens

Bereid de betaomschrijving, testinstructies en beoordelaarstoegang voor. Een externe TestFlight-build kan een beta-review nodig hebben. Rond schermafbeeldingen, supportlink, privacyverklaring en de privacy-antwoorden in App Store Connect af. Neem ook de toegang tot deelnemersgegevens door bevoegde beheerders mee.

Apple: https://developer.apple.com/testflight/
Apple: https://developer.apple.com/app-store/app-privacy-details/

## 5. Productie en App Store als aparte stap

Na een geslaagde acceptatiepilot volgt een afzonderlijke beslissing over productie-API, app-links, APNs en de serverinstelling van de Release-build. De backend is nu bewust acceptance-only: een App Store-upload maakt productie niet automatisch beschikbaar.

Zie `release.md` voor signing en `activity-admin.md` voor de beheerrechten en widgetbeveiliging.
