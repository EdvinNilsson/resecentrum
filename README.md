# Resecentrum: Journey planner for Västtrafik

Resecentrum is a journey planner app for public transport in Västra Götaland, Sweden, operated by Västtrafik.
It is made with Flutter, and it can be built for both Android and iOS.
The app is currently available on Google Play and is only available in Swedish.

<a href='https://play.google.com/store/apps/details?id=ga.edvin.resecentrum'><img alt='Get it on Google Play' src='https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png' height='80px'/></a>

## Screenshots

![Screenshot 1](https://play-lh.googleusercontent.com/LufvM5sfC3Ku681yQBPvg02kRSZMlX2sF9PN59KG_Ad7W11DaeQtmvXY_HEWZE131NI)
![Screenshot 2](https://play-lh.googleusercontent.com/M6sZ6SarTWBEw9cYyWS_LDHrTGQtNwheRRavsJEjOndJKa_3fvaMIA8ljM-NqB_HExM)
![Screenshot 3](https://play-lh.googleusercontent.com/xw5PNQ2g9KlHLo53aL1JkoS9FlzmpsyKw1Xgz_PzDsEoJPDNoGlgjl0LWk9sVfdcqfk)
![Screenshot 4](https://play-lh.googleusercontent.com/JwJgS7_4QdGFLWgMp_v9wWspx8uWhsmnBy5zrqxFfc4Q5Vwoht3r212krWX8mjQAbw)
![Screenshot 5](https://play-lh.googleusercontent.com/KByORx_3TZil7lXspI4RHGP8s33-0kpXPR9q60NGXuxqmLkV6y-ffGrEy5_aBsxD8Tm1)
![Screenshot 6](https://play-lh.googleusercontent.com/WqVW7o6ZVssYesv-VabzZjX2louGTRojWGnY3c98o0uySmRHc9wroQrNWxUZfFUkvfY)
![Screenshot 7](https://play-lh.googleusercontent.com/aA7p3x7hAz7lcnWxavqxz8sgpV9mH7_ywcSjEiu9W_d_alxGkgn7a_PZEEHg23O64FoX)
![Screenshot 8](https://play-lh.googleusercontent.com/e9GHAY_7LsSfB8VE11VbkspPBSoi7UYyTqRFualxPT80_IKNtPc36pTAeKCiNVUIv7M)

## Build notes

Run ```flutter pub run build_runner build``` for code generation.

When building, assign API keys with ```--dart-define```.  
For example ```flutter build apk --dart-define AUTH_KEY=<insert-auth-key> --dart-define AUTH_SECRET=<insert-auth-secret> --dart-define TRAFIKVERKET_KEY=<insert-api-key>```.

You can get API keys from [Västtrafik's developer portal](https://developer.vasttrafik.se/) by creating an application that subscribes to both `Reseplaneraren v2` and `TrafficSituations v1`.
To get additional information about train journeys, you need an API key from [Trafikverket](https://api.trafikinfo.trafikverket.se/).

<sub>Google Play and the Google Play logo are trademarks of Google LLC.</sub>
